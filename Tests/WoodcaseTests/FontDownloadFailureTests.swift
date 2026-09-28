//
//  FontDownloadFailureTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// "Could not reach Google Fonts" and "Google Fonts has no such family", told apart.
///
/// The resolver used to swallow every fetch error and end in `familyNotFound`, so an agent
/// whose sandbox blocked the download was told, in effect, that Lobster does not exist —
/// the UFTI pilot of 2026-09-10 lost its fonts to that. These pin the two outcomes apart,
/// at the error and at the warning a render prints.
@Suite("Font download failures")
struct FontDownloadFailureTests {
    /// A family name no font registry will ever answer to.
    static let family = "Woodcase No Such Face"

    /// What a blocked sandbox looks like from the resolver's side of the seam.
    static let unreachable = RemoteFetchError.unreachable(NetworkFailure(
        reason: .hostNotFound, domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, proxy: nil
    ))

    @Test("A transport failure is networkUnavailable, not familyNotFound")
    func transportFailureIsNotNotFound() async {
        let resolver = Self.makeResolver(responses: ["METADATA.pb": .failure(Self.unreachable)])
        do {
            _ = try await resolver.fetchMetadata(family: Self.family)
            Issue.record("expected a throw")
        } catch let GoogleFontError.networkUnavailable(family, failure) {
            #expect(family == Self.family)
            #expect(failure == Self.unreachable)
        } catch {
            Issue.record("expected networkUnavailable, got \(error)")
        }
    }

    @Test("A server error is networkUnavailable too: the family may well exist")
    func serverErrorIsNotNotFound() async {
        let resolver = Self.makeResolver(responses: [
            "METADATA.pb": .failure(RemoteFetchError.httpError(statusCode: 503)),
        ])
        do {
            _ = try await resolver.fetchMetadata(family: Self.family)
            Issue.record("expected a throw")
        } catch GoogleFontError.networkUnavailable {
        } catch {
            Issue.record("expected networkUnavailable, got \(error)")
        }
    }

    @Test("The render warning for a blocked network says so, with the reason")
    func warningNamesNetwork() async throws {
        let resolver = Self.makeResolver(responses: ["METADATA.pb": .failure(Self.unreachable)])
        let diagnostics = PenDiagnosticCollector()

        try await resolver.prepareFonts(for: Self.missingFontDocument(), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains(Self.family))
        #expect(message.contains("could not be downloaded"))
        #expect(message.contains(NetworkFailure.Reason.hostNotFound.explanation))
        #expect(!message.contains("no family named"))
    }

    @Test("The render warning for an unknown family says Google Fonts has none")
    func warningNamesMissingFamily() async throws {
        let resolver = Self.makeResolver(responses: [:])
        let diagnostics = PenDiagnosticCollector()

        try await resolver.prepareFonts(for: Self.missingFontDocument(), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains("Google Fonts has no family named \"\(Self.family)\""))
        #expect(!message.contains("could not be downloaded"))
    }

    @Test("A TTF that fails after its metadata arrived is a download failure")
    func ttfFailureIsDownloadFailure() async throws {
        let resolver = Self.makeResolver(responses: [
            "METADATA.pb": .success(Data(Self.metadata.utf8)),
            ".ttf": .failure(Self.unreachable),
        ])
        let diagnostics = PenDiagnosticCollector()

        try await resolver.prepareFonts(for: Self.missingFontDocument(), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains("could not be downloaded"))
    }

    // MARK: - Support

    /// METADATA.pb for ``family``.
    static let metadata = """
    name: "Woodcase No Such Face"
    fonts {
      name: "Woodcase No Such Face"
      style: "normal"
      weight: 400
      filename: "WoodcaseNoSuchFace-Regular.ttf"
    }
    """

    /// A resolver over a fresh temporary cache and a fetcher answering `responses`.
    private static func makeResolver(responses: [String: Result<Data, Error>]) -> GoogleFontResolver {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FontDownloadFailure-\(UUID().uuidString)", isDirectory: true)
        return GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: root),
            fetcher: MockFontFetcher(responses: responses)
        )
    }

    /// The fixture naming ``family``.
    private static func missingFontDocument() throws -> PenDocument {
        let url = try #require(
            Bundle.module.url(forResource: "font-missing", withExtension: "pen", subdirectory: "Fixtures")
        )
        return try PenParser.parse(contentsOf: url)
    }
}
