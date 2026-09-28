//
//  CurlDataFetcherTests.swift
//  Woodcase
//

#if os(macOS)
    import Foundation
    import Testing
    @testable import Woodcase

    /// The curl-backed fetcher, against `file://` URLs and loopback servers only.
    ///
    /// Every request here either stays on disk or goes to 127.0.0.1, and each fetcher is
    /// given an explicit environment, so no test inherits a proxy or reaches the network.
    @Suite("curl fetcher", .hangGuard)
    struct CurlDataFetcherTests {
        /// An environment with no proxy variables.
        static let noProxy: [String: String] = [:]

        static func temporaryFile(_ contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("CurlDataFetcherTests-\(UUID().uuidString).txt")
            try Data(contents.utf8).write(to: url)
            return url
        }

        // MARK: - Transport

        @Test("A readable file:// URL returns its bytes")
        func fileURL() async throws {
            let file = try Self.temporaryFile("hello, curl")
            defer { try? FileManager.default.removeItem(at: file) }

            let data = try await CurlDataFetcher(environment: Self.noProxy).fetch(url: file)

            #expect(data == Data("hello, curl".utf8))
        }

        @Test("A body far larger than a pipe's buffer arrives whole, and ending in a newline")
        func largeBody() async throws {
            // 1 MiB of text lines: sixteen times a pipe's 64 KiB, so a reader that waits for
            // curl to exit before draining its output deadlocks here.
            let line = String(repeating: "x", count: 1023) + "\n"
            let contents = String(repeating: line, count: 1024)
            let file = try Self.temporaryFile(contents)
            defer { try? FileManager.default.removeItem(at: file) }
            let fetcher = CurlDataFetcher(environment: Self.noProxy)

            let data = try await BoundedWait.value { try await fetcher.fetch(url: file) }

            #expect(data == Data(contents.utf8))
        }

        @Test("An empty body is empty data, not an error")
        func emptyBody() async throws {
            let file = try Self.temporaryFile("")
            defer { try? FileManager.default.removeItem(at: file) }

            #expect(try await CurlDataFetcher(environment: Self.noProxy).fetch(url: file).isEmpty)
        }

        @Test("A missing file is unreachable, with curl's exit code and domain")
        func missingFile() async {
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("CurlDataFetcherTests-missing-\(UUID().uuidString)")

            await #expect(throws: RemoteFetchError.unreachable(NetworkFailure(
                reason: .other, domain: CurlDataFetcher.errorDomain, code: 37, proxy: nil
            ))) {
                try await CurlDataFetcher(environment: Self.noProxy).fetch(url: missing)
            }
        }

        @Test("A 200 from the server returns its body")
        func okStatus() async throws {
            let server = try await LoopbackHTTPServer.start(reply: LoopbackHTTPServer.response(
                status: 200, reason: "OK", body: "font bytes"
            ))
            defer { server.stop() }
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/Lobster.ttf"))

            let data = try await CurlDataFetcher(environment: Self.noProxy).fetch(url: url)

            #expect(data == Data("font bytes".utf8))
        }

        @Test("A 404 from the server is an HTTP error carrying the status")
        func notFoundStatus() async throws {
            let server = try await LoopbackHTTPServer.start(reply: LoopbackHTTPServer.response(
                status: 404, reason: "Not Found", body: "404: Not Found"
            ))
            defer { server.stop() }
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/METADATA.pb"))

            await #expect(throws: RemoteFetchError.httpError(statusCode: 404)) {
                try await CurlDataFetcher(environment: Self.noProxy).fetch(url: url)
            }
        }

        @Test("A proxy nobody listens on is the proxy, named without its credentials")
        func closedProxy() async throws {
            // Bind and release a port so nothing is listening on it.
            let server = try await LoopbackHTTPServer.start(reply: .silence)
            let port = server.port
            server.stop()
            let environment = ["HTTPS_PROXY": "http://user:secret@127.0.0.1:\(port)"]
            let url = try #require(URL(string: "https://example.invalid/font.ttf"))

            let error = await #expect(throws: RemoteFetchError.self) {
                try await CurlDataFetcher(environment: environment).fetch(url: url)
            }

            guard case let .unreachable(failure) = error else {
                Issue.record("expected unreachable, got \(String(describing: error))")
                return
            }
            #expect(failure.reason == .proxyUnreachable)
            #expect(failure.domain == CurlDataFetcher.errorDomain)
            #expect(failure.proxy == "127.0.0.1:\(port)")
            #expect(!failure.description.contains("secret"))
        }

        @Test("A proxy that answers CONNECT with 407 rejected the credentials")
        func proxyChallenge() async throws {
            let proxy = try await LoopbackHTTPServer.start(reply: LoopbackHTTPServer.response(
                status: 407, reason: "Proxy Authentication Required",
                headers: ["Proxy-Authenticate: Basic realm=\"test\""]
            ))
            defer { proxy.stop() }
            let environment = ["HTTPS_PROXY": "http://127.0.0.1:\(proxy.port)"]
            let url = try #require(URL(string: "https://example.invalid/font.ttf"))

            let error = await #expect(throws: RemoteFetchError.self) {
                try await CurlDataFetcher(environment: environment).fetch(url: url)
            }

            guard case let .unreachable(failure) = error else {
                Issue.record("expected unreachable, got \(String(describing: error))")
                return
            }
            #expect(failure.reason == .proxyAuthenticationFailed)
        }

        @Test("A server that never answers times out within the fetcher's bound")
        func silentServer() async throws {
            let server = try await LoopbackHTTPServer.start(reply: .silence)
            defer { server.stop() }
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/slow"))
            let fetcher = CurlDataFetcher(timeout: .seconds(1), environment: Self.noProxy)

            let error = await #expect(throws: RemoteFetchError.self) {
                try await BoundedWait.value { try await fetcher.fetch(url: url) }
            }

            guard case let .unreachable(failure) = error else {
                Issue.record("expected unreachable, got \(String(describing: error))")
                return
            }
            #expect(failure.reason == .timedOut)
            #expect(failure.code == 28)
        }

        @Test("An executable that cannot be launched is unreachable, not a crash")
        func missingExecutable() async throws {
            let fetcher = CurlDataFetcher(
                executable: URL(fileURLWithPath: "/nonexistent/curl-\(UUID().uuidString)"),
                environment: Self.noProxy
            )
            let file = try Self.temporaryFile("x")
            defer { try? FileManager.default.removeItem(at: file) }

            let error = await #expect(throws: RemoteFetchError.self) {
                try await fetcher.fetch(url: file)
            }

            guard case let .unreachable(failure) = error else {
                Issue.record("expected unreachable, got \(String(describing: error))")
                return
            }
            #expect(failure.reason == .other)
        }

        // MARK: - Arguments

        @Test("The URL is one argument after --url, and the user's .curlrc is ignored")
        func arguments() throws {
            let url = try #require(URL(string: "https://example.com/a b;$(rm -rf ~)"))

            let arguments = CurlDataFetcher(timeout: .seconds(5), environment: Self.noProxy)
                .arguments(for: url)

            #expect(arguments.first == "-q")
            let index = try #require(arguments.firstIndex(of: "--url"))
            #expect(arguments[index + 1] == url.absoluteString)
            #expect(arguments.last == url.absoluteString)
            #expect(arguments.contains("--max-time"))
            #expect(!arguments.contains("--output"), "the body comes back on standard output, not in a file")
        }

        // MARK: - Exit codes

        @Test("curl's exit codes map to reasons", arguments: [
            (Int32(5), 0, false, NetworkFailure.Reason.proxyUnreachable),
            (6, 0, false, .hostNotFound),
            (7, 0, false, .cannotConnect),
            (7, 0, true, .proxyUnreachable),
            (28, 0, false, .timedOut),
            (35, 0, false, .cannotConnect),
            (52, 0, false, .cannotConnect),
            (56, 0, false, .cannotConnect),
            (56, 407, true, .proxyAuthenticationFailed),
            (56, 403, true, .proxyUnreachable),
            (60, 0, false, .certificateUntrusted),
            (97, 0, true, .proxyUnreachable),
            (37, 0, false, .other),
        ])
        func exitCodes(exitCode: Int32, connectStatus: Int, viaProxy: Bool, reason: NetworkFailure.Reason) {
            let failure = CurlDataFetcher.failure(
                exitCode: exitCode, proxyConnectStatus: connectStatus, proxy: viaProxy ? "127.0.0.1:1" : nil
            )
            #expect(failure.reason == reason)
            #expect(failure.domain == CurlDataFetcher.errorDomain)
            #expect(failure.code == Int(exitCode))
        }
    }
#endif
