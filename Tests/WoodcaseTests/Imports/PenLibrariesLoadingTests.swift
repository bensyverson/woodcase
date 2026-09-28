//
//  PenLibrariesLoadingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Where a document's `imports` are looked for, and what a failed look reports.
///
/// Every rule here is Pen's, established with the `pen` CLI headless (0.3.9) and
/// recorded in `project/2026-09-26-pen-import-resolution.md`: a path is relative to the
/// importing file's directory and nothing else, absolute paths and `file:` URLs are
/// read as they stand, `pencil:` names a library bundled with Pen itself, and a
/// library's own imports are never followed.
struct PenLibrariesLoadingTests {
    // MARK: - Helpers

    /// A library with one reusable frame.
    private static let library = """
    {"version":"2.17","children":[{"id":"Cmp01","type":"frame","reusable":true,"width":10,"height":10}]}
    """

    /// A fresh directory for one test's files.
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenLibrariesLoadingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `text` to `path` under `directory`, creating folders on the way.
    @discardableResult
    private func write(_ text: String, to path: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        return url
    }

    /// A host document declaring `imports` and nothing else.
    private func host(_ imports: [String: String]) -> PenDocument {
        PenDocument(imports: imports, children: [])
    }

    // MARK: - Where a path is looked for

    @Test("A bare name is the file beside the document")
    func bareNameIsSibling() throws {
        let directory = try scratch()
        try write(Self.library, to: "kit.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(importedBy: host(["K": "kit.lib.pen"]), at: hostURL)

        #expect(libraries.problems.isEmpty)
        #expect(libraries.documents["kit.lib.pen"]?.children.first?.id == "Cmp01")
    }

    @Test("A missing sibling is not found, naming the one path that was tried")
    func missingSiblingIsNotFound() throws {
        let directory = try scratch()
        let hostURL = directory.appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(importedBy: host(["K": "kit.lib.pen"]), at: hostURL)

        #expect(libraries.documents.isEmpty)
        #expect(libraries.problems == [.notFound(
            alias: "K", path: "kit.lib.pen",
            url: directory.appendingPathComponent("kit.lib.pen").standardizedFileURL
        )])
    }

    @Test("A ./ or ../ path is relative to the document's own directory")
    func relativePathsResolveFromTheDocument() throws {
        let directory = try scratch()
        try write(Self.library, to: "shared/icons.lib.pen", in: directory)
        try write(Self.library, to: "app/local.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app/app.pen")

        let libraries = PenLibraries.load(
            importedBy: host(["I": "../shared/icons.lib.pen", "L": "./local.lib.pen"]),
            at: hostURL
        )

        #expect(libraries.problems.isEmpty)
        #expect(Set(libraries.documents.keys) == ["../shared/icons.lib.pen", "./local.lib.pen"])
    }

    @Test("An absolute path and a file: URL are read as they stand")
    func absoluteLocationsResolve() throws {
        let directory = try scratch()
        let libraryURL = try write(Self.library, to: "elsewhere/kit.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app/app.pen")

        let libraries = PenLibraries.load(
            importedBy: host(["A": libraryURL.path, "U": libraryURL.absoluteString]),
            at: hostURL
        )

        #expect(libraries.problems.isEmpty)
        #expect(libraries.documents.count == 2)
    }

    @Test("A pencil: library is one Pen bundles, which is never looked for on disk")
    func pencilSchemeIsBundled() throws {
        let directory = try scratch()
        // A file of the same name beside the document must not stand in for it: Pen
        // reads `pencil:` from its own install, never from the document's folder.
        try write(Self.library, to: "shadcn.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(
            importedBy: host(["S": "pencil:shadcn.lib.pen"]), at: hostURL
        )

        #expect(libraries.documents.isEmpty)
        #expect(libraries.problems == [.bundled(alias: "S", path: "pencil:shadcn.lib.pen")])
    }

    @Test("A remote URL is reported, never fetched")
    func remoteURLIsNotFetched() throws {
        let hostURL = try scratch().appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(
            importedBy: host(["R": "https://example.com/kit.lib.pen"]), at: hostURL
        )

        #expect(libraries.documents.isEmpty)
        #expect(libraries.problems == [.remote(alias: "R", path: "https://example.com/kit.lib.pen")])
    }

    // MARK: - What a read reports

    @Test("A file that is not a readable .pen document is unreadable, and the load goes on")
    func unreadableLibraryIsReported() throws {
        let directory = try scratch()
        try write("not json", to: "broken.lib.pen", in: directory)
        try write(Self.library, to: "kit.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(
            importedBy: host(["B": "broken.lib.pen", "K": "kit.lib.pen"]), at: hostURL
        )

        #expect(Array(libraries.documents.keys) == ["kit.lib.pen"])
        #expect(libraries.problems.count == 1)
        guard case let .unreadable(alias, path, reason) = libraries.problems.first else {
            Issue.record("expected an unreadable problem, got \(libraries.problems)")
            return
        }
        #expect(alias == "B")
        #expect(path == "broken.lib.pen")
        #expect(!reason.isEmpty)
    }

    @Test("A library's own imports are not followed, and the load says so")
    func nestedImportsAreNotFollowed() throws {
        let directory = try scratch()
        try write(Self.library, to: "inner.lib.pen", in: directory)
        try write("""
        {"version":"2.17","imports":{"I":"inner.lib.pen"},"children":[]}
        """, to: "outer.lib.pen", in: directory)
        let hostURL = directory.appendingPathComponent("app.pen")

        let libraries = PenLibraries.load(importedBy: host(["O": "outer.lib.pen"]), at: hostURL)

        #expect(Array(libraries.documents.keys) == ["outer.lib.pen"])
        #expect(libraries.problems == [.notFollowed(
            alias: "O", path: "outer.lib.pen", nestedAlias: "I", nestedPath: "inner.lib.pen"
        )])
    }

    @Test("A document that imports itself is its own library, read once and not followed")
    func selfImportUsesTheDocument() throws {
        let directory = try scratch()
        let hostURL = directory.appendingPathComponent("app.pen")
        // Nothing is written at hostURL: the document in hand is the library, so the
        // load cannot be reading the file a second time.
        var document = host(["S": "app.pen"])
        document.children = [PenNode(
            id: "Own01", common: PenNodeCommon(reusable: true), kind: .frame(PenNode.FrameData())
        )]

        let libraries = PenLibraries.load(importedBy: document, at: hostURL)

        #expect(libraries.documents["app.pen"] == document)
        // Its copy's own imports — itself — are not followed, as for any library.
        #expect(libraries.problems == [.notFollowed(
            alias: "S", path: "app.pen", nestedAlias: "S", nestedPath: "app.pen"
        )])
    }
}
