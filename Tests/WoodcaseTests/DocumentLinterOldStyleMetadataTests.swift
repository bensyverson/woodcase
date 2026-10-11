//
//  DocumentLinterOldStyleMetadataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `metadata-old-style`: a notice naming the Woodcase metadata keys a node still keeps
/// under their old spelling, and the migration that moves them; and that migration
/// itself, as the edit `woodcase migrate` applies. See DocC `PenMetadataNamespace`.
@MainActor
struct DocumentLinterOldStyleMetadataTests {
    private func document() throws -> EditableDocument {
        let url = try #require(Bundle.module.url(
            forResource: "metadata-old-style", withExtension: "pen", subdirectory: "Fixtures"
        ))
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    @Test("Each node holding old spellings gets one notice naming them")
    func namesOldSpellings() throws {
        let findings = try DocumentLinter.findings(in: document()).filter { $0.check == .metadataOldStyle }

        #expect(findings.map(\.nodeID) == ["Btn01", "Nte01"])
        #expect(findings.allSatisfy { $0.severity == .notice })
        let button = try #require(findings.first)
        #expect(button.message.contains("_props"))
        #expect(button.message.contains("_role"))
        #expect(button.message.contains("woodcase migrate"))
        let note = try #require(findings.last)
        for key in ["type", "state", "author", "tint"] {
            #expect(note.message.contains(key), "the notice omits \(key): \(note.message)")
        }
        #expect(!note.message.contains("kind"))
    }

    @Test("The check is a notice")
    func checkIsANotice() {
        #expect(LintCheck.metadataOldStyle.rawValue == "metadata-old-style")
        #expect(LintCheck.metadataOldStyle.severity == .notice)
    }

    @Test("The migration is one metadata write per node with old spellings, and leaves none behind")
    func migrationConvertsTheFile() throws {
        let document = try document()

        let operations = document.oldStyleWoodcaseKeyMigration()
        #expect(operations.count == 2)
        for operation in operations {
            try document.apply(operation)
        }

        #expect(document.oldStyleWoodcaseKeyMigration().isEmpty)
        #expect(try DocumentLinter.findings(in: document).filter { $0.check == .metadataOldStyle }.isEmpty)
        let note = try #require(document.node(id: "Nte01")?.common.metadata)
        #expect(note.type == "woodcase")
        #expect(note.extensions["kind"] == .string("question"))
        #expect(note[woodcase: .type] == .string("postit"))
        #expect(note[woodcase: .tint] == .string("#A5D6A7"))
        let button = try #require(document.node(id: "Btn01")?.common.metadata)
        #expect(button.type == "component")
        #expect(button.extensions["_role"] == nil)
        #expect(button[woodcase: .props] == .dictionary(["label": .string("Label")]))
    }
}
