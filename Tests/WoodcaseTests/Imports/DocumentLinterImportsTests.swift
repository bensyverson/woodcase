//
//  DocumentLinterImportsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Lint sees the document the renderer draws: imported components resolved, and an
/// import that resolved nothing reported once, at the top.
struct DocumentLinterImportsTests {
    /// Lints a file the way `woodcase lint` does: through a transaction.
    static func lint(_ url: URL) async throws -> [LintFinding] {
        try await PenFileTransaction.read(at: url) { document in
            try DocumentLinter.findings(in: document)
        }.value
    }

    @Test("A cross-import ref and slash-path overrides through imported components lint clean")
    func importUsingFixtureLintsClean() async throws {
        let url = try PenFileTransactionLibrariesTests.fixtures().appendingPathComponent("app.pen")

        let findings = try await Self.lint(url)

        #expect(findings.isEmpty, "\(LintFormatter.text(findings))")
    }

    @Test("A library that is not there is one import-not-found finding, at the document")
    func missingLibraryIsOneFinding() async throws {
        let directory = try PenFileTransactionLibrariesTests.copy(["app.pen"])

        let findings = try await Self.lint(directory.appendingPathComponent("app.pen"))

        let imports = findings.filter { $0.check == .importNotFound }
        #expect(imports.count == 1)
        #expect(imports.first?.nodeID == nil)
        #expect(imports.first?.severity == .error)
        #expect(findings.first?.check == .importNotFound, "document-level findings lead")
    }

    @Test("Each kind of import problem maps to its check")
    func problemsMapToChecks() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        document.readContext = PenReadContext(libraries: PenLibraries(problems: [
            .notFound(alias: "A", path: "a.pen", url: URL(fileURLWithPath: "/nowhere/a.pen")),
            .unreadable(alias: "B", path: "b.pen", reason: "not JSON"),
            .bundled(alias: "C", path: "pencil:c.lib.pen"),
            .remote(alias: "D", path: "https://example.com/d.pen"),
            .notFollowed(alias: "E", path: "e.pen", nestedAlias: "F", nestedPath: "f.pen"),
        ]))

        let checks = try DocumentLinter.findings(in: document).map(\.check)

        #expect(checks == [
            .importNotFound, .importUnreadable, .importNotFound, .importNotFound, .importNotFollowed,
        ])
    }

    @Test("A broken ref through a declared import says which library it looked in")
    func brokenRefNamesTheLibrary() async throws {
        let directory = try PenFileTransactionLibrariesTests.copy(["app.pen"])

        let findings = try await Self.lint(directory.appendingPathComponent("app.pen"))

        let broken = try #require(findings.first { $0.check == .brokenRef && $0.nodeID == "Ins01" })
        #expect(broken.message.contains("kit.lib.pen"))
    }
}
