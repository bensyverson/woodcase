//
//  ApplyLocalFailClosedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `applyLocal(_:)` must refuse an invalid operation *before* the CRDT sees it.
///
/// One scenario per guard ``EditableDocument/apply(_:)`` enforces: each asserts that
/// the refusal is the same ``EditingError`` in both modes, and that a refused edit
/// leaves the CRDT state and the flat store exactly as they were — nothing to
/// replicate to a peer.
@MainActor
struct ApplyLocalFailClosedTests {
    // MARK: - Fixture

    /// A component with one instance, plus a frame holding a rectangle and an empty
    /// frame, and one variable, import and theme axis.
    private func makeDocument() -> PenDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let instance = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Submit"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "Inner"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect, inner]))
        )
        return PenDocument(
            themes: ["mode": ["light", "dark"]],
            imports: ["ui": "./ui.pen"],
            variables: ["primary": PenVariable(type: .color, value: .simple(.string("#FF0000")))],
            children: [component, instance, frame]
        )
    }

    /// The observable flat store, captured for a before/after comparison.
    private struct FlatStore: Equatable {
        var nodes: [String: PenNode]
        var children: [String: [String]]
        var parents: [String: String]
        var rootOrder: [String]
        var variables: [String: PenVariable]?
        var imports: [String: String]?
        var themes: [String: [String]]?

        @MainActor
        init(of document: EditableDocument) {
            nodes = document.nodes
            children = document.children
            parents = document.parents
            rootOrder = document.rootOrder
            variables = document.variables
            imports = document.imports
            themes = document.themes
        }
    }

    // MARK: - Scenarios

    /// One invalid operation per guard, named for the guard it trips.
    enum InvalidCase: String, CaseIterable, CustomTestStringConvertible {
        case insertDuplicateID
        case insertParentMissing
        case insertParentCannotHaveChildren
        case insertIndexTooLarge
        case insertIndexNegative
        case insertRootIndexTooLarge
        case deleteMissingNode
        case deleteStrandsInstances
        case moveMissingNode
        case moveParentMissing
        case moveParentCannotHaveChildren
        case moveCreatesCycle
        case moveIndexTooLarge
        case updateCommonMissingNode
        case updateKindMissingNode
        case setPropertiesMissingNode
        case setPropertiesUnknownKey
        case setPropertiesBadValue
        case overrideMissingNode
        case overrideNotARef
        case overrideTargetMissing
        case detachMissingNode
        case detachNotARef
        case addVariableExists
        case updateVariableMissing
        case removeVariableMissing
        case addImportExists
        case updateImportMissing
        case removeImportMissing
        case addThemeAxisExists
        case updateThemeAxisMissing
        case removeThemeAxisMissing

        var testDescription: String {
            rawValue
        }

        /// A node that is not yet in the fixture, for the insert scenarios.
        private static func newNode(id: String = "new1") -> PenNode {
            PenNode(id: id, common: PenNodeCommon(name: "New"), kind: .rectangle(PenNode.RectangleData()))
        }

        /// The invalid operation this scenario applies.
        var operation: EditOperation {
            switch self {
            case .insertDuplicateID:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(id: "r1"), parentID: "f1"))
            case .insertParentMissing:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(), parentID: "nope"))
            case .insertParentCannotHaveChildren:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(), parentID: "r1"))
            case .insertIndexTooLarge:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(), parentID: "f1", index: 99))
            case .insertIndexNegative:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(), parentID: "f1", index: -1))
            case .insertRootIndexTooLarge:
                .insertNode(EditOperation.InsertNode(node: Self.newNode(), parentID: nil, index: 99))
            case .deleteMissingNode:
                .deleteNode(EditOperation.DeleteNode(nodeID: "nope"))
            case .deleteStrandsInstances:
                .deleteNode(EditOperation.DeleteNode(nodeID: "comp1"))
            case .moveMissingNode:
                .moveNode(EditOperation.MoveNode(nodeID: "nope", newParentID: "f1"))
            case .moveParentMissing:
                .moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: "nope"))
            case .moveParentCannotHaveChildren:
                .moveNode(EditOperation.MoveNode(nodeID: "label", newParentID: "r1"))
            case .moveCreatesCycle:
                .moveNode(EditOperation.MoveNode(nodeID: "f1", newParentID: "inner"))
            case .moveIndexTooLarge:
                .moveNode(EditOperation.MoveNode(nodeID: "label", newParentID: "inner", index: 5))
            case .updateCommonMissingNode:
                .updateCommon(EditOperation.UpdateCommon(nodeID: "nope", common: PenNodeCommon(name: "X")))
            case .updateKindMissingNode:
                .updateKind(EditOperation.UpdateKind(nodeID: "nope", kind: .rectangle(PenNode.RectangleData())))
            case .setPropertiesMissingNode:
                .setProperties(EditOperation.SetProperties(nodeID: "nope", properties: ["common.name": .string("X")]))
            case .setPropertiesUnknownKey:
                .setProperties(EditOperation.SetProperties(nodeID: "r1", properties: ["kind.bogus": .int(1)]))
            case .setPropertiesBadValue:
                .setProperties(EditOperation.SetProperties(nodeID: "r1", properties: ["common.opacity": .bool(true)]))
            case .overrideMissingNode:
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "nope", descendantID: "label", properties: ["name": .string("X")]
                ))
            case .overrideNotARef:
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "f1", descendantID: "label", properties: ["name": .string("X")]
                ))
            case .overrideTargetMissing:
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "ref1", descendantID: "missing", properties: ["name": .string("X")]
                ))
            case .detachMissingNode:
                .detachRef(EditOperation.DetachRef(refNodeID: "nope"))
            case .detachNotARef:
                .detachRef(EditOperation.DetachRef(refNodeID: "f1"))
            case .addVariableExists:
                .addVariable(EditOperation.AddVariable(
                    name: "primary", variable: PenVariable(type: .color, value: .simple(.string("#00FF00")))
                ))
            case .updateVariableMissing:
                .updateVariable(EditOperation.UpdateVariable(
                    name: "nope", variable: PenVariable(type: .color, value: .simple(.string("#00FF00")))
                ))
            case .removeVariableMissing:
                .removeVariable(EditOperation.RemoveVariable(name: "nope"))
            case .addImportExists:
                .addImport(EditOperation.AddImport(alias: "ui", path: "./other.pen"))
            case .updateImportMissing:
                .updateImport(EditOperation.UpdateImport(alias: "nope", path: "./other.pen"))
            case .removeImportMissing:
                .removeImport(EditOperation.RemoveImport(alias: "nope"))
            case .addThemeAxisExists:
                .addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["a", "b"]))
            case .updateThemeAxisMissing:
                .updateThemeAxis(EditOperation.UpdateThemeAxis(name: "nope", options: ["a", "b"]))
            case .removeThemeAxisMissing:
                .removeThemeAxis(EditOperation.RemoveThemeAxis(name: "nope"))
            }
        }

        /// The ``EditingError`` case the operation must be refused with.
        var expectedGuard: String {
            switch self {
            case .insertDuplicateID: "duplicateNodeID"
            case .insertParentMissing, .moveParentMissing: "parentNotFound"
            case .insertParentCannotHaveChildren, .moveParentCannotHaveChildren: "cannotHaveChildren"
            case .insertIndexTooLarge, .insertIndexNegative, .insertRootIndexTooLarge, .moveIndexTooLarge:
                "invalidIndex"
            case .deleteMissingNode, .moveMissingNode, .updateCommonMissingNode, .updateKindMissingNode,
                 .setPropertiesMissingNode, .overrideMissingNode, .detachMissingNode:
                "nodeNotFound"
            case .deleteStrandsInstances: "componentHasInstances"
            case .moveCreatesCycle: "wouldCreateCycle"
            case .setPropertiesUnknownKey: "unknownProperty"
            case .setPropertiesBadValue: "propertyTypeMismatch"
            case .overrideNotARef, .detachNotARef: "notARefNode"
            case .overrideTargetMissing: "overrideTargetNotFound"
            case .addVariableExists: "variableAlreadyExists"
            case .updateVariableMissing, .removeVariableMissing: "variableNotFound"
            case .addImportExists: "importAlreadyExists"
            case .updateImportMissing, .removeImportMissing: "importNotFound"
            case .addThemeAxisExists: "themeAxisAlreadyExists"
            case .updateThemeAxisMissing, .removeThemeAxisMissing: "themeAxisNotFound"
            }
        }
    }

    // MARK: - Tests

    @Test(
        "An invalid operation in CRDT mode throws the same error and replicates nothing",
        arguments: InvalidCase.allCases
    )
    func invalidOperationFailsClosed(scenario: InvalidCase) throws {
        let operation = scenario.operation

        let plain = EditableDocument(from: makeDocument())
        guard let plainError = Self.thrown(by: { try plain.apply(operation) }) as? EditingError else {
            Issue.record("apply(_:) did not throw an EditingError in non-CRDT mode")
            return
        }
        #expect(Self.guardName(of: plainError) == scenario.expectedGuard)

        let peer = EditableDocument(from: makeDocument(), peerID: PeerID(rawValue: "peerA"))
        let crdt = try #require(peer.crdtDocument)
        let crdtBefore = crdt.snapshot()
        let storeBefore = FlatStore(of: peer)

        guard let localError = Self.thrown(by: { _ = try peer.applyLocal(operation) }) as? EditingError else {
            Issue.record("applyLocal(_:) did not throw an EditingError in CRDT mode")
            return
        }

        #expect(localError == plainError)
        #expect(crdt.snapshot() == crdtBefore, "CRDT state changed for a refused operation")
        #expect(FlatStore(of: peer) == storeBefore, "The flat store changed for a refused operation")
        #expect(peer.pendingOperations(since: VectorClock()).isEmpty)
    }

    @Test("A move to a negative index is refused rather than trapping")
    func moveToNegativeIndexIsRefused() throws {
        let operation = EditOperation.moveNode(
            EditOperation.MoveNode(nodeID: "label", newParentID: "inner", index: -1)
        )

        let plain = EditableDocument(from: makeDocument())
        #expect(throws: EditingError.invalidIndex(index: -1, count: 0)) {
            try plain.apply(operation)
        }
        #expect(plain.parents["label"] == "comp1")

        let peer = EditableDocument(from: makeDocument(), peerID: PeerID(rawValue: "peerA"))
        let crdt = try #require(peer.crdtDocument)
        let crdtBefore = crdt.snapshot()
        #expect(throws: EditingError.invalidIndex(index: -1, count: 0)) {
            _ = try peer.applyLocal(operation)
        }
        #expect(crdt.snapshot() == crdtBefore)
    }

    @Test("A move within one parent counts the index against the list it will land in")
    func moveWithinParentValidatesAgainstPostRemovalCount() throws {
        let editable = EditableDocument(from: makeDocument())
        // f1 holds [r1, inner]; moving r1 within f1 leaves one sibling, so 1 is the
        // last valid index and 2 is out of bounds.
        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: "f1", index: 1)))
        #expect(editable.children["f1"] == ["inner", "r1"])

        #expect(throws: EditingError.invalidIndex(index: 2, count: 1)) {
            try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "r1", newParentID: "f1", index: 2)))
        }
        #expect(editable.children["f1"] == ["inner", "r1"], "A refused move left the node detached")
    }

    // MARK: - Helpers

    /// Runs `body` and returns whatever it threw, or `nil` if it returned.
    private static func thrown(by body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    /// The name of an ``EditingError``'s case, so a scenario can name the guard it
    /// expects without spelling out the payload.
    private static func guardName(of error: EditingError) -> String {
        switch error {
        case .nodeNotFound: "nodeNotFound"
        case .duplicateNodeID: "duplicateNodeID"
        case .invalidNodeID: "invalidNodeID"
        case .parentNotFound: "parentNotFound"
        case .cannotHaveChildren: "cannotHaveChildren"
        case .invalidIndex: "invalidIndex"
        case .wouldCreateCycle: "wouldCreateCycle"
        case .variableNotFound: "variableNotFound"
        case .variableAlreadyExists: "variableAlreadyExists"
        case .importNotFound: "importNotFound"
        case .importAlreadyExists: "importAlreadyExists"
        case .themeAxisNotFound: "themeAxisNotFound"
        case .themeAxisAlreadyExists: "themeAxisAlreadyExists"
        case .notARefNode: "notARefNode"
        case .unknownProperty: "unknownProperty"
        case .propertyTypeMismatch: "propertyTypeMismatch"
        case .ambiguousAddress: "ambiguousAddress"
        case .addressNotFound: "addressNotFound"
        case .componentHasInstances: "componentHasInstances"
        case .componentTypeChange: "componentTypeChange"
        case .overrideTargetNotFound: "overrideTargetNotFound"
        case .overrideOnOwnSlotContent: "overrideOnOwnSlotContent"
        case .overrideValueRejected: "overrideValueRejected"
        case .rootOverrideKeyReserved: "rootOverrideKeyReserved"
        case .rootOverrideValueRejected: "rootOverrideValueRejected"
        case .revisionConflict: "revisionConflict"
        }
    }
}
