//
//  CurlDataFetcher.swift
//  Woodcase
//

#if os(macOS)
    import Foundation
    import os

    /// A ``RemoteDataFetching`` that runs `/usr/bin/curl`, for where Apple's TLS cannot
    /// verify a certificate.
    ///
    /// Inside the Claude Code Bash sandbox the process cannot reach
    /// `com.apple.trustd.agent`, so every `URLSession` HTTPS request fails before a byte
    /// arrives. curl verifies with LibreSSL against `/etc/ssl/cert.pem`, reads the proxy
    /// variables (credentials included) itself, and resolves `localhost` without the
    /// system resolver — everything that sandbox needs. So ``StandardDataFetcher`` puts this
    /// behind ``URLSessionDataFetcher`` in a ``TrustFallbackDataFetcher``; it is not meant
    /// as the first stack.
    ///
    /// curl is run directly, never through a shell: the URL is one argument after `--url`,
    /// and the user's `.curlrc` is ignored. The body comes back on standard output, which
    /// is drained while curl runs so a large font cannot fill the pipe and stall the child;
    /// curl's `--write-out` report follows it as a last line. No temporary file is written:
    /// `FileManager`'s temporary directory ignores `$TMPDIR`, and a sandbox that allows only
    /// `$TMPDIR` denies it. The fetch keeps the typed-error contract: a status other than
    /// 200 is ``RemoteFetchError/httpError(statusCode:)``, and a curl failure is
    /// ``RemoteFetchError/unreachable(_:)`` with a ``NetworkFailure`` in ``errorDomain``
    /// whose code is curl's exit code. Proxy credentials travel only in the child's
    /// environment; nothing here prints them.
    public struct CurlDataFetcher: RemoteDataFetching {
        /// The curl macOS ships.
        public static let standardExecutable = URL(fileURLWithPath: "/usr/bin/curl")
        /// The ``NetworkFailure/domain`` of a failure curl reported; its code is curl's
        /// exit code.
        public static let errorDomain = "curl"
        /// How long one fetch may take, start to finish — `URLSession`'s default request
        /// timeout, applied here to the whole transfer.
        public static let defaultTimeout: Duration = .seconds(60)

        /// The curl binary to run.
        public let executable: URL
        /// How long one fetch may take, start to finish (curl's `--max-time`).
        public let timeout: Duration
        /// The environment curl runs with, which carries its proxy variables.
        public let environment: [String: String]

        /// Creates a fetcher.
        ///
        /// - Parameters:
        ///   - executable: The curl binary, ``standardExecutable`` by default.
        ///   - timeout: How long one fetch may take, ``defaultTimeout`` by default.
        ///   - environment: The environment curl runs with, `ProcessInfo`'s by default. Its
        ///     proxy variables route the request, as they do for ``URLSessionDataFetcher``.
        public init(
            executable: URL = standardExecutable,
            timeout: Duration = defaultTimeout,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.executable = executable
            self.timeout = timeout
            self.environment = environment
        }

        /// Fetches the URL with curl.
        ///
        /// - Parameter url: The URL to fetch.
        /// - Returns: The response body.
        /// - Throws: ``RemoteFetchError/httpError(statusCode:)`` for any HTTP status other
        ///   than 200, ``RemoteFetchError/unreachable(_:)`` when curl got no answer or could
        ///   not be launched, and `CancellationError` when the task was canceled.
        public func fetch(url: URL) async throws -> Data {
            let proxy: String? = if case let .proxy(endpoint) = ProxyEnvironment(environment: environment)
                .route(for: url) { endpoint.description } else { nil }
            let exitCode: Int32
            let output: Data
            do {
                (exitCode, output) = try await run(arguments: arguments(for: url))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RemoteFetchError.unreachable(
                    NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: proxy)
                )
            }

            let (body, httpStatus, connectStatus) = Self.split(output)
            guard exitCode == 0 else {
                throw RemoteFetchError.unreachable(
                    Self.failure(exitCode: exitCode, proxyConnectStatus: connectStatus, proxy: proxy)
                )
            }
            // A `file://` transfer reports no status at all (`000`), and is not an error.
            if httpStatus != 0, httpStatus != Self.okStatus {
                throw RemoteFetchError.httpError(statusCode: httpStatus)
            }
            return body
        }

        // MARK: - Arguments

        /// The `--write-out` report, written after the body: a newline, the origin's final
        /// status, then the proxy's answer to `CONNECT` (`000` when there was none). It
        /// holds no newline of its own, so it is everything after the output's last one.
        static let writeOutFormat = "\\n%{http_code} %{http_connect}"

        private static let okStatus = 200

        /// The argument vector for one fetch — never a shell string.
        ///
        /// `-q` must come first to skip `.curlrc`. `--location` follows redirects as
        /// `URLSession` does; `--proto` and `--proto-redir` keep curl to the schemes a
        /// fetcher is asked for, so a redirect cannot turn into some other protocol.
        ///
        /// - Parameter url: The URL to fetch. It is always the last argument, after `--url`.
        /// - Returns: The arguments, without the executable.
        func arguments(for url: URL) -> [String] {
            [
                "-q",
                "--silent",
                "--location",
                "--proto", "=http,https,file",
                "--proto-redir", "=http,https",
                "--max-time", Self.seconds(timeout),
                "--write-out", Self.writeOutFormat,
                "--url", url.absoluteString,
            ]
        }

        /// A duration as curl's decimal seconds, e.g. `60` or `0.5`.
        private static func seconds(_ duration: Duration) -> String {
            let (seconds, attoseconds) = duration.components
            let fraction = Double(attoseconds) / 1e18
            return fraction == 0 ? String(seconds) : String(Double(seconds) + fraction)
        }

        /// Separates curl's output into the body and the two statuses of the report that
        /// ends it; a status that is absent reads as `0`.
        private static func split(_ output: Data) -> (body: Data, http: Int, connect: Int) {
            let newline = UInt8(ascii: "\n")
            guard let last = output.lastIndex(of: newline) else { return (Data(), 0, 0) }
            let fields = String(decoding: output[(last + 1)...], as: UTF8.self)
                .split(separator: " ")
                .map { Int($0) ?? 0 }
            return (Data(output[..<last]), fields.first ?? 0, fields.dropFirst().first ?? 0)
        }

        // MARK: - Process

        /// Runs curl and collects its standard output, without holding a thread of the
        /// cooperative pool: a dispatch worker drains the pipe while curl writes, the
        /// termination handler reports the exit, and the continuation resumes when both
        /// are in. Canceling the task terminates the child.
        private func run(arguments: [String]) async throws -> (exitCode: Int32, output: Data) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe

            try Task.checkCancellation()
            let result: (Int32, Data) = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let collected = OSAllocatedUnfairLock(initialState: (exitCode: Int32(-1), output: Data()))
                    let group = DispatchGroup()
                    group.enter()
                    process.terminationHandler = { finished in
                        collected.withLock { $0.exitCode = finished.terminationStatus }
                        group.leave()
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        // EOF arrives when curl exits and its end of the pipe closes.
                        let output = pipe.fileHandleForReading.readDataToEndOfFile()
                        collected.withLock { $0.output = output }
                        group.leave()
                    }
                    group.notify(queue: .global()) {
                        continuation.resume(returning: collected.withLock { ($0.exitCode, $0.output) })
                    }
                }
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
            if process.terminationReason == .uncaughtSignal {
                try Task.checkCancellation()
            }
            return result
        }

        // MARK: - Exit codes

        /// curl's `CURLE_*` exit codes that this fetcher tells apart.
        private enum ExitCode {
            static let couldNotResolveProxy: Int32 = 5
            static let couldNotResolveHost: Int32 = 6
            static let couldNotConnect: Int32 = 7
            static let timedOut: Int32 = 28
            static let tlsConnectFailed: Int32 = 35
            static let gotNothing: Int32 = 52
            static let sendFailed: Int32 = 55
            static let receiveFailed: Int32 = 56
            static let peerFailedVerification: Int32 = 60
            static let proxyHandshake: Int32 = 97
        }

        /// The HTTP status a proxy answers a `CONNECT` with when it wants credentials.
        private static let proxyAuthenticationRequired = 407

        /// Classifies a curl failure.
        ///
        /// - Parameters:
        ///   - exitCode: curl's exit status.
        ///   - proxyConnectStatus: The proxy's answer to `CONNECT` (`%{http_connect}`), `0`
        ///     when there was none. A refused tunnel exits 56, like a dropped connection;
        ///     this is how the two are told apart.
        ///   - proxy: The proxy in use, as `host:port`, or `nil`.
        /// - Returns: The failure, in ``errorDomain`` with the exit code as its code.
        static func failure(exitCode: Int32, proxyConnectStatus: Int, proxy: String?) -> NetworkFailure {
            let tunnelRefused = proxyConnectStatus != 0 && proxyConnectStatus != okStatus
            let reason: NetworkFailure.Reason = switch exitCode {
            case ExitCode.couldNotResolveProxy, ExitCode.proxyHandshake:
                .proxyUnreachable
            case ExitCode.couldNotResolveHost:
                .hostNotFound
            case ExitCode.couldNotConnect:
                proxy == nil ? .cannotConnect : .proxyUnreachable
            case ExitCode.timedOut:
                .timedOut
            case ExitCode.receiveFailed where proxyConnectStatus == proxyAuthenticationRequired:
                .proxyAuthenticationFailed
            case ExitCode.receiveFailed where tunnelRefused:
                .proxyUnreachable
            case ExitCode.tlsConnectFailed, ExitCode.gotNothing, ExitCode.sendFailed, ExitCode.receiveFailed:
                .cannotConnect
            case ExitCode.peerFailedVerification:
                .certificateUntrusted
            default:
                .other
            }
            return NetworkFailure(reason: reason, domain: errorDomain, code: Int(exitCode), proxy: proxy)
        }
    }
#endif
