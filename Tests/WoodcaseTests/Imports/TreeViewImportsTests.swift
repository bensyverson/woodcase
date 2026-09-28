//
//  TreeViewImportsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// `tree` settles an instance of an imported component to the component's size, and
/// can step into it.
struct TreeViewImportsTests {
    static func rows(expandInstances: Bool = false) async throws -> [TreeRow] {
        let url = try PenFileTransactionLibrariesTests.fixtures().appendingPathComponent("app.pen")
        return try await PenFileTransaction.read(at: url) { document in
            try TreeView.rows(of: document, expandInstances: expandInstances)
        }.value
    }

    @Test("An instance of an imported component settles to the component's size")
    func importedInstanceHasARect() async throws {
        let rows = try await Self.rows()

        let chip = try #require(rows.first { $0.id == "Ins01" })
        #expect(chip.rect?.width == 80)
        #expect(chip.rect?.height == 24)
    }

    @Test("Expanding instances steps into an imported component's nodes")
    func expandedInstanceListsImportedNodes() async throws {
        let rows = try await Self.rows(expandInstances: true)

        let label = try #require(rows.first { $0.id == "Ins02/K:Cc001/K:Txt01" })
        #expect(label.type == "text")
        #expect((label.rect?.width ?? 0) > 0)
    }
}
