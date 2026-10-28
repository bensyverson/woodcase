//
//  PenFormat221Tests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers format 2.21, which Pen 1.2.16 writes: the model is 2.21, a 2.21 file reads with
/// no newer-version notice, and a 2.20 file still reads and is written back as 2.21 with
/// nothing else rewritten, as Pen 1.2.16 does. 2.21 only adds the shader effect, so no
/// migration rule runs between them.
struct PenFormat221Tests {
    // MARK: - Helpers

    private func document(version: String, children: String) -> Data {
        Data(#"{"version":"\#(version)","children":\#(children)}"#.utf8)
    }

    /// A rectangle with an inner shadow and an image fill with an explicit 2.20 mode.
    private let shadowAndImage = #"""
    [{"id":"R1","type":"rectangle","width":10,"height":10,
      "fill":{"type":"image","url":"./a.png","mode":"contain"},
      "effect":{"type":"shadow","shadowType":"inner","color":"#000000","blur":4}}]
    """#

    // MARK: - The version

    @Test("The model writes format 2.21, and 2.21 is a version Pen has been seen to write")
    func currentVersionIs221() {
        #expect(PenFormatVersion.current == PenFormatVersion(major: 2, minor: 21))
        #expect(PenDocument.currentFormatVersion == "2.21")
        #expect(PenFormatVersion.observedModern.contains(PenFormatVersion(major: 2, minor: 21)))
        #expect(PenFormatVersion.observedModern.contains(PenFormatVersion(major: 2, minor: 20)))
    }

    @Test("A 2.21 file reads with no newer-version notice and keeps its version")
    func format221ReadsQuietly() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.21", children: shadowAndImage), diagnostics: diagnostics)
        #expect(doc.version == "2.21")
        #expect(doc.formatRelation == .current)
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    // MARK: - A 2.20 file

    @Test("A 2.20 file reads silently, only its version restamped, and reports the model's version")
    func format220ReadsSilently() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.20", children: shadowAndImage), diagnostics: diagnostics)
        #expect(doc.version == "2.21")
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
        let rules = PenLegacyMigrator.rules(upgrading: PenFormatVersion(major: 2, minor: 20))
        #expect(rules.count == 1)
        #expect(rules.first is PenVersionMigrationRule)
    }

    @Test("A 2.20 file is written back as 2.21 with nothing else changed")
    func format220WritesAs221() throws {
        let original = document(version: "2.20", children: shadowAndImage)
        let outcome = try PenFileMigrator.migrate(original)
        #expect(!outcome.wasAlreadyCurrent)
        #expect(outcome.writtenVersion == "2.21")
        let before = try PenParser.parse(original)
        let after = try PenParser.parse(outcome.data)
        #expect(after.children == before.children)
    }
}
