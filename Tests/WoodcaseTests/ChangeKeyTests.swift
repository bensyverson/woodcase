//
//  ChangeKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every ``EditOperation`` case maps to the ``ChangeKey``s it writes.
struct ChangeKeyTests {
    /// One sample per case, each with the keys it must produce.
    ///
    /// ``caseName(_:)`` switches over every case without a `default`, so a new case
    /// does not compile until it is named there — and the count check below then fails
    /// until it has a sample here.
    private static func samples() -> [(EditOperation, Set<ChangeKey>)] {
        let inserted = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "New"),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "n2", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData())),
            ]))
        )
        let replacement = PenNode(
            id: "f2",
            common: PenNodeCommon(name: "Frame2b"),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "c9", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData())),
            ]))
        )
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        return [
            (.insertNode(EditOperation.InsertNode(node: inserted, parentID: "f1", index: 0)),
             [.existence(node: "n1"), .existence(node: "n2"), .placement(node: "n1")]),
            (.deleteNode(EditOperation.DeleteNode(nodeID: "f2")),
             [.existence(node: "f2"), .existence(node: "c4"), .placement(node: "f2")]),
            (.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: "f2", index: 0)),
             [.placement(node: "c1")]),
            (.replaceSubtree(EditOperation.ReplaceSubtree(node: replacement)),
             [.property(node: "f2", path: "common.name"), .existence(node: "c4"), .existence(node: "c9")]),
            (.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: PenNodeCommon(name: "Renamed"))),
             [.property(node: "c1", path: "common.name")]),
            (.updateKind(EditOperation.UpdateKind(
                nodeID: "c1",
                kind: .rectangle(PenNode.RectangleData(width: .fixed(50), height: .fixed(40)))
            )), [.property(node: "c1", path: "kind.width")]),
            (.setProperties(EditOperation.SetProperties(
                nodeID: "c1", properties: ["kind.width": 10, "common.name": "n"]
            )), [.property(node: "c1", path: "kind.width"), .property(node: "c1", path: "common.name")]),
            (.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#0000ff"], unset: ["opacity"]
            )), [
                .override(ref: "ref1", descendant: "inner", key: "fill"),
                .override(ref: "ref1", descendant: "inner", key: "opacity"),
            ]),
            (.overrideRoot(EditOperation.OverrideRoot(refNodeID: "ref1", properties: ["width": 10], unset: ["height"])),
             [.rootOverride(ref: "ref1", key: "width"), .rootOverride(ref: "ref1", key: "height")]),
            (.detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
             Set([ChangeKey.existence(node: "ref1")] + plannedIDs(of: "ref1").map { .existence(node: $0) })),
            (.addVariable(EditOperation.AddVariable(name: "accent", variable: variable)), [.variable(name: "accent")]),
            (.updateVariable(EditOperation.UpdateVariable(name: "primary", variable: variable)),
             [.variable(name: "primary")]),
            (.removeVariable(EditOperation.RemoveVariable(name: "primary")), [.variable(name: "primary")]),
            (.addImport(EditOperation.AddImport(alias: "kit", path: "kit.pen")), [.importAlias("kit")]),
            (.updateImport(EditOperation.UpdateImport(alias: "lib", path: "lib2.pen")), [.importAlias("lib")]),
            (.removeImport(EditOperation.RemoveImport(alias: "lib")), [.importAlias("lib")]),
            (.addThemeAxis(EditOperation.AddThemeAxis(name: "density", options: ["a", "b"])), [.themeAxis("density")]),
            (.updateThemeAxis(EditOperation.UpdateThemeAxis(name: "mode", options: ["light"])), [.themeAxis("mode")]),
            (.removeThemeAxis(EditOperation.RemoveThemeAxis(name: "mode")), [.themeAxis("mode")]),
            (.setDocumentProperties(EditOperation.SetDocumentProperties(
                properties: ["fileToken": "t1", "extras.custom": true]
            )), [.document("fileToken"), .document("extras.custom")]),
        ]
    }

    /// The case's name, from a switch the compiler checks for exhaustiveness.
    private static func caseName(_ operation: EditOperation) -> String {
        switch operation {
        case .insertNode: "insertNode"
        case .deleteNode: "deleteNode"
        case .moveNode: "moveNode"
        case .replaceSubtree: "replaceSubtree"
        case .updateCommon: "updateCommon"
        case .updateKind: "updateKind"
        case .setProperties: "setProperties"
        case .overrideDescendant: "overrideDescendant"
        case .overrideRoot: "overrideRoot"
        case .detachRef: "detachRef"
        case .addVariable: "addVariable"
        case .updateVariable: "updateVariable"
        case .removeVariable: "removeVariable"
        case .addImport: "addImport"
        case .updateImport: "updateImport"
        case .removeImport: "removeImport"
        case .addThemeAxis: "addThemeAxis"
        case .updateThemeAxis: "updateThemeAxis"
        case .removeThemeAxis: "removeThemeAxis"
        case .setDocumentProperties: "setDocumentProperties"
        }
    }

    /// Every case `caseName` names; keep in step with it.
    private static let allCaseNames: Set<String> = [
        "insertNode", "deleteNode", "moveNode", "replaceSubtree", "updateCommon", "updateKind",
        "setProperties", "overrideDescendant", "overrideRoot", "detachRef", "addVariable",
        "updateVariable", "removeVariable", "addImport", "updateImport", "removeImport",
        "addThemeAxis", "updateThemeAxis", "removeThemeAxis", "setDocumentProperties",
    ]

    /// The ids a detach of `refID` will insert, from the plan the detach itself uses.
    private static func plannedIDs(of refID: String) -> [String] {
        let document = SessionTestDocuments.make()
        guard let plan = try? document.detachPlans(for: [refID]).first else { return [] }
        return document.collectInsertedIDs(in: plan.subtree)
    }

    @Test("every EditOperation case has a sample")
    func everyCaseSampled() {
        let sampled = Set(Self.samples().map { Self.caseName($0.0) })
        #expect(sampled == Self.allCaseNames)
    }

    @Test("every sample maps to exactly its keys, without duplicates")
    func everySampleMapsToItsKeys() throws {
        for (operation, expected) in Self.samples() {
            let document = SessionTestDocuments.make()
            let keys = try ChangeKey.keys(of: operation, in: document)
            #expect(Set(keys) == expected, "\(Self.caseName(operation))")
            #expect(keys.count == Set(keys).count, "\(Self.caseName(operation)) repeats a key")
        }
    }

    @Test("a change of node type writes the whole kind and every path of both kinds")
    func kindCaseChange() throws {
        let document = SessionTestDocuments.make()
        let operation = EditOperation.updateKind(EditOperation.UpdateKind(
            nodeID: "c1", kind: .text(PenNode.TextData(content: .literal("hi")))
        ))
        let keys = try Set(ChangeKey.keys(of: operation, in: document))
        #expect(keys.contains(.property(node: "c1", path: ChangeKey.wholeKindPath)))
        #expect(keys.contains(.property(node: "c1", path: "kind.cornerRadius")))
        #expect(keys.contains(.property(node: "c1", path: "kind.content")))
        #expect(!keys.contains(.property(node: "c1", path: "common.name")))
    }

    @Test("a detaching delete also writes the existence of each instance it detaches")
    func detachingDelete() throws {
        let document = SessionTestDocuments.make()
        let operation = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach))
        let keys = try Set(ChangeKey.keys(of: operation, in: document))
        let planned = Self.plannedIDs(of: "ref1")
        #expect(planned.count == 3)
        #expect(keys == Set([
            .existence(node: "comp1"), .existence(node: "inner"), .existence(node: "label"), .placement(node: "comp1"),
            .existence(node: "ref1"),
        ] + planned.map { ChangeKey.existence(node: $0) }))
    }

    @Test("an operation on a missing node throws rather than keying nothing")
    func missingNodeThrows() {
        let document = SessionTestDocuments.make()
        #expect(throws: EditingError.self) {
            try ChangeKey.keys(of: .updateCommon(EditOperation.UpdateCommon(nodeID: "nope", common: PenNodeCommon())),
                               in: document)
        }
    }
}
