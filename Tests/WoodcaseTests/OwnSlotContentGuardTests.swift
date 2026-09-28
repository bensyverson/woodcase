//
//  OwnSlotContentGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The override guard and lint on the two keys Pen was measured on
/// (`project/2026-09-26-slot-override-keys.md`, follow-up).
///
/// A key naming content an instance wrote into a nested instance's slot itself is
/// dropped by Pen, so a raw ``EditOperation/OverrideDescendant`` storing one is refused
/// and lint reports one a file already holds, pointing at the address form, which
/// rewrites the change into the slot fill (``SlotFillRewriteTests``). A path naming a
/// nested component's instance applies, so both accept it.
@MainActor
struct OwnSlotContentGuardTests {
    /// `Box` places `Inn`, an instance of `Slt` with an empty `Hole`; `Use` fills that
    /// hole with `NewY` itself. `Cmp` places `Mid`, whose component `Bar` places `Dot`.
    private static func document(descendants: String = "") throws -> EditableDocument {
        let json = """
        {"version": "2.17", "children": [
          {"id": "Red", "type": "frame", "reusable": true, "width": 20, "height": 20, "fill": "#FF0000"},
          {"id": "Bar", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Dot", "type": "ref", "ref": "Red", "x": 5, "y": 5}]},
          {"id": "Cmp", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Mid", "type": "ref", "ref": "Bar"}]},
          {"id": "Slt", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Hole", "type": "frame", "name": "Hole", "width": 150, "height": 30, "children": []}]},
          {"id": "Box", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Inn", "type": "ref", "name": "Inner", "ref": "Slt"}]},
          {"id": "Use", "type": "ref", "name": "Use", "ref": "Box", "descendants": {
            "Inn/Hole": {"children": [{"id": "NewY", "type": "rectangle", "width": 20, "height": 20}]}\(descendants)}},
          {"id": "Two", "type": "ref", "ref": "Cmp"}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    @Test("A raw override op on content the instance wrote into a nested slot is refused")
    func nestedOwnSlotContentIsRefused() throws {
        let doc = try Self.document()
        for key in ["Inn/NewY", "NewY"] {
            let error = #expect(throws: EditingError.self) {
                try doc.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "Use", descendantID: key, properties: ["fill": .string("#0000FF")]
                )))
            }
            switch error {
            case let .overrideOnOwnSlotContent(_, _, slotPath)?:
                #expect(slotPath == "Use/Inner/Hole")
            case .overrideTargetNotFound?:
                // The bare id is no key the instance's walk lists at all.
                #expect(key == "NewY")
            default:
                Issue.record("\(key) was accepted or refused for another reason: \(String(describing: error))")
            }
        }
    }

    @Test("Lint reports a stored key naming the instance's own slot content")
    func lintReportsOwnSlotContentKey() throws {
        let doc = try Self.document(descendants: ##", "Inn/NewY": {"fill": "#0000FF"}"##)

        let findings = try DocumentLinter.findings(in: doc).filter { $0.check == .overrideTargetNotFound }

        #expect(findings.map(\.nodeID) == ["Use"])
        let message = findings.first?.message ?? ""
        #expect(message.contains("Use/Inner/Hole"), "\(message)")
        // The remedy is the address form, which writes the value into the fill.
        #expect(message.contains("woodcase override <file> Use/Inn/NewY fill=<value>"), "\(message)")
    }

    @Test("A path naming a nested component's instance is accepted")
    func pathToNestedInstanceIsAccepted() throws {
        let doc = try Self.document()

        try doc.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Two", descendantID: "Mid/Dot", properties: ["fill": .string("#00FF00")]
        )))

        #expect(try DocumentLinter.findings(in: doc).filter { $0.check == .overrideTargetNotFound }.isEmpty)
    }
}
