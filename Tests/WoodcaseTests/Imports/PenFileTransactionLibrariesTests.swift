//
//  PenFileTransactionLibrariesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A transaction reads the libraries its file's `imports` name, once, as it parses
/// the file, and hands them to the body as read context.
struct PenFileTransactionLibrariesTests {
    /// The `Fixtures/imports` directory.
    static func fixtures() throws -> URL {
        try #require(Bundle.module.url(forResource: "imports", withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Copies the named fixtures from `Fixtures/imports` into a fresh directory.
    static func copy(_ names: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionLibrariesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.copyItem(
                at: fixtures().appendingPathComponent(name),
                to: directory.appendingPathComponent(name)
            )
        }
        return directory
    }

    @Test("A read hands the body the libraries its file imports, and where it came from")
    func readLoadsLibraries() async throws {
        let url = try Self.fixtures().appendingPathComponent("app.pen")

        let outcome = try await PenFileTransaction.read(at: url) { document in
            (
                Array(document.readContext.libraries.documents.keys),
                document.readContext.libraries.problems,
                document.readContext.sourceURL
            )
        }

        #expect(outcome.value.0 == ["kit.lib.pen"])
        #expect(outcome.value.1.isEmpty)
        #expect(outcome.value.2 == url)
    }

    @Test("A write transaction reads them too, and writes nothing for having read them")
    func runLoadsLibrariesAndWritesNothing() async throws {
        let directory = try Self.copy(["app.pen", "kit.lib.pen"])
        let url = directory.appendingPathComponent("app.pen")

        let outcome = try await PenFileTransaction.run(at: url) { document in
            document.readContext.libraries.documents.count
        }

        #expect(outcome.value == 1)
        #expect(outcome.commit == .unchanged)
    }

    @Test("A missing library is a problem on the read context, never a failed read")
    func missingLibraryIsNotAFailure() async throws {
        let directory = try Self.copy(["app.pen"])
        let url = directory.appendingPathComponent("app.pen")

        let problems = try await PenFileTransaction.read(at: url) { document in
            document.readContext.libraries.problems
        }.value

        #expect(problems == [.notFound(
            alias: "K", path: "kit.lib.pen",
            url: directory.appendingPathComponent("kit.lib.pen").standardizedFileURL
        )])
    }

    @Test("The font resolver a caller names is the one the document settles through")
    func fontsReachTheDocument() async throws {
        let url = try Self.fixtures().appendingPathComponent("app.pen")
        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("PenFileTransactionLibrariesTests-\(UUID().uuidString)")),
            fetcher: MockFontFetcher()
        )

        let named = try await PenFileTransaction.read(at: url, fonts: resolver) { document in
            document.readContext.fonts === resolver
        }.value
        let unnamed = try await PenFileTransaction.read(at: url) { document in
            document.readContext.fonts == nil
        }.value

        #expect(named)
        #expect(unnamed)
    }
}
