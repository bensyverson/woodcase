//
//  ImageDownloadFailureTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The remote-image warning says *why* a download failed, the same way
/// ``FontDownloadFailureTests`` pins it for fonts: a blocked network reads
/// differently from a 404, and a fetcher that throws something of its own still
/// reads as unreachable rather than as a silent, reasonless "could not be fetched".
@Suite("Image download failures")
struct ImageDownloadFailureTests {
    static let url = "https://images.example.com/missing.jpg"

    /// What a blocked sandbox looks like from the resolver's side of the seam.
    static let unreachable = RemoteFetchError.unreachable(NetworkFailure(
        reason: .hostNotFound, domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, proxy: nil
    ))

    /// An error a custom ``RemoteDataFetching`` implementation might throw that is
    /// neither case of ``RemoteFetchError`` — the resolver has never seen this type.
    private struct CustomFetcherError: Error {}

    /// A fetcher that throws whatever `errors` says for a URL, keyed by its exact
    /// string, and a plain 404 for anything not named.
    private struct ThrowingImageFetcher: RemoteDataFetching {
        var errors: [String: Error] = [:]

        func fetch(url: URL) async throws -> Data {
            if let error = errors[url.absoluteString] { throw error }
            throw RemoteFetchError.httpError(statusCode: 404)
        }
    }

    private static func makeResolver(errors: [String: Error]) -> (RemoteImageResolver, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let resolver = RemoteImageResolver(
            cache: RemoteImageCache(rootDirectory: tempDir),
            fetcher: ThrowingImageFetcher(errors: errors)
        )
        return (resolver, tempDir)
    }

    private static func document(withFill url: String) -> PenDocument {
        PenDocument(children: [
            PenNode(
                id: "1",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(
                    fills: .single(.image(PenFill.PenImageFill(url: url)))
                ))
            ),
        ])
    }

    @Test("An unreachable network says why, with the NetworkFailure's reason")
    func warningNamesNetworkFailure() async throws {
        let (resolver, tempDir) = Self.makeResolver(errors: [Self.url: Self.unreachable])
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let diagnostics = PenDiagnosticCollector()

        await resolver.prepareImages(for: Self.document(withFill: Self.url), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains(Self.url))
        #expect(message.contains(NetworkFailure.Reason.hostNotFound.explanation))
    }

    @Test("An HTTP error names the status code")
    func warningNamesStatusCode() async throws {
        let (resolver, tempDir) = Self.makeResolver(
            errors: [Self.url: RemoteFetchError.httpError(statusCode: 404)]
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let diagnostics = PenDiagnosticCollector()

        await resolver.prepareImages(for: Self.document(withFill: Self.url), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains("HTTP 404"))
    }

    @Test("An error from a custom fetcher reads as unreachable, not as a silent miss")
    func warningFromUnknownErrorReadsAsUnreachable() async throws {
        let (resolver, tempDir) = Self.makeResolver(errors: [Self.url: CustomFetcherError()])
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let diagnostics = PenDiagnosticCollector()

        await resolver.prepareImages(for: Self.document(withFill: Self.url), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains(NetworkFailure.Reason.other.explanation))
    }
}
