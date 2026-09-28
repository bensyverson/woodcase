//
//  EditOperationSetPropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationSetPropertiesTests {
    // MARK: - Helpers

    /// frame(f1) > rect(r1), where r1 has a full set of properties to disturb.
    private func makeDoc() -> EditableDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", x: .literal(10), y: .literal(20), opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100),
                height: .fixed(50),
                cornerRadius: .uniform(.literal(4)),
                fills: .single(.shorthand("red"))
            ))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect]))
        )
        return EditableDocument(from: PenDocument(children: [frame]))
    }

    private func setProperties(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    // MARK: - Criterion 1: one property changes, everything else survives

    @Test("setProperties on a rectangle's fill leaves every other property untouched")
    func fillPatchLeavesTheRestAlone() throws {
        let editable = makeDoc()
        let before = try #require(editable.node(id: "r1"))

        try editable.apply(setProperties("r1", ["kind.fills": .string("blue")]))

        let after = try #require(editable.node(id: "r1"))
        guard case let .rectangle(data) = after.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.fills == .single(.shorthand("blue")))
        #expect(data.width == .fixed(100))
        #expect(data.height == .fixed(50))
        #expect(data.cornerRadius == .uniform(.literal(4)))
        #expect(after.common == before.common)
    }

    @Test("A fill patch round-trips through materialize()")
    func fillPatchRoundTripsThroughMaterialize() throws {
        let editable = makeDoc()
        try editable.apply(setProperties("r1", ["kind.fills": .string("blue")]))

        let materialized = editable.materialize()
        let data = try JSONEncoder().encode(materialized)
        let reloaded = try JSONDecoder().decode(PenDocument.self, from: data)
        let reopened = EditableDocument(from: reloaded)

        #expect(reopened.node(id: "r1") == editable.node(id: "r1"))
        #expect(reopened.node(id: "f1") == editable.node(id: "f1"))
    }

    @Test("setProperties writes common and kind paths in one operation")
    func mixedPathsInOneOperation() throws {
        let editable = makeDoc()

        try editable.apply(setProperties("r1", [
            "common.name": .string("Renamed"),
            "kind.width": .int(240),
        ]))

        let node = try #require(editable.node(id: "r1"))
        #expect(node.common.name == "Renamed")
        #expect(node.common.x == .literal(10))
        guard case let .rectangle(data) = node.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.width == .fixed(240))
    }

    @Test("An empty property map is a no-op, not an error")
    func emptyMapIsNoOp() throws {
        let editable = makeDoc()
        let before = editable.node(id: "r1")
        try editable.apply(setProperties("r1", [:]))
        #expect(editable.node(id: "r1") == before)
    }

    @Test("setProperties rejects an unknown node ID")
    func unknownNodeThrows() {
        let editable = makeDoc()
        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(self.setProperties("missing", ["kind.width": .int(1)]))
        }
    }

    // MARK: - Criterion 2: an unknown key names the key and the node

    @Test("An unknown property key fails with an error naming the key and the node")
    func unknownKeyThrows() {
        let editable = makeDoc()
        #expect(throws: EditingError.unknownProperty(nodeID: "r1", key: "kind.fontSize", nodeType: "rectangle")) {
            try editable.apply(self.setProperties("r1", ["kind.fontSize": .int(14)]))
        }
    }

    @Test("A wrong-typed value fails with a type mismatch naming both shapes")
    func typeMismatchThrows() {
        let editable = makeDoc()
        #expect(throws: EditingError.propertyTypeMismatch(
            nodeID: "r1", key: "common.opacity", expected: "a number or a $variable", actual: "a boolean"
        )) {
            try editable.apply(self.setProperties("r1", ["common.opacity": .bool(true)]))
        }
    }

    // MARK: - Atomicity

    @Test("One bad key in a map of three changes nothing")
    func atomicOnUnknownKey() {
        let editable = makeDoc()
        let before = editable.node(id: "r1")

        #expect(throws: EditingError.self) {
            try editable.apply(self.setProperties("r1", [
                "kind.width": .int(300),
                "kind.nonsense": .int(1),
                "common.name": .string("Renamed"),
            ]))
        }

        #expect(editable.node(id: "r1") == before)
    }

    @Test("One bad value in a map of three changes nothing")
    func atomicOnTypeMismatch() {
        let editable = makeDoc()
        let before = editable.node(id: "r1")

        #expect(throws: EditingError.self) {
            try editable.apply(self.setProperties("r1", [
                "kind.width": .int(300),
                "kind.height": .bool(false),
                "common.name": .string("Renamed"),
            ]))
        }

        #expect(editable.node(id: "r1") == before)
    }

    // MARK: - Clearing

    @Test("A null value clears the property")
    func nullClearsProperty() throws {
        let editable = makeDoc()
        try editable.apply(setProperties("r1", ["kind.cornerRadius": .null, "common.name": .null]))

        let node = try #require(editable.node(id: "r1"))
        #expect(node.common.name == nil)
        guard case let .rectangle(data) = node.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.cornerRadius == nil)
        #expect(data.fills == .single(.shorthand("red")))
    }

    // MARK: - Inverse

    @Test("The inverse of setProperties restores the prior values of the same keys")
    func inverseRestoresPriorValues() throws {
        let editable = makeDoc()
        let before = try #require(editable.node(id: "r1"))

        let op = setProperties("r1", ["kind.fills": .string("blue"), "kind.width": .int(300)])
        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        #expect(editable.node(id: "r1") != before)

        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.node(id: "r1") == before)
    }

    @Test("The inverse of a clearing setProperties restores the cleared value")
    func inverseRestoresClearedValue() throws {
        let editable = makeDoc()
        let before = try #require(editable.node(id: "r1"))

        let op = setProperties("r1", ["kind.cornerRadius": .null])
        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.node(id: "r1") == before)
    }

    @Test("The inverse names exactly the keys the forward operation named")
    func inverseCarriesSameKeys() throws {
        let editable = makeDoc()
        let op = setProperties("r1", ["kind.fills": .string("blue"), "common.name": .string("X")])

        let inverse = try editable.prepareInverse(of: op)
        #expect(inverse.count == 1)
        guard case let .setProperties(params) = inverse[0] else {
            Issue.record("Expected setProperties inverse")
            return
        }
        #expect(Set(params.properties.keys) == ["kind.fills", "common.name"])
        #expect(params.properties["common.name"] == .string("Rect"))
    }

    @Test("prepareInverse of setProperties on a missing node throws")
    func inverseOnMissingNodeThrows() {
        let editable = makeDoc()
        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            _ = try editable.prepareInverse(of: self.setProperties("missing", ["kind.width": .int(1)]))
        }
    }

    // MARK: - Dirty classification

    @Test("A fill change is classified renderOnly")
    func fillChangeIsRenderOnly() throws {
        let editable = makeDoc()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        try editable.apply(setProperties("r1", ["kind.fills": .string("blue")]))

        #expect(editable.dirtyRenderNodeIDs.contains("r1"))
        #expect(!editable.dirtyLayoutNodeIDs.contains("r1"))
    }

    @Test("A width change is classified layout and dirties ancestors")
    func widthChangeIsLayout() throws {
        let editable = makeDoc()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        try editable.apply(setProperties("r1", ["kind.width": .int(300)]))

        #expect(editable.dirtyLayoutNodeIDs.contains("r1"))
        #expect(editable.dirtyLayoutNodeIDs.contains("f1"))
    }

    @Test("A common.x change is classified layout")
    func commonPositionChangeIsLayout() throws {
        let editable = makeDoc()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        try editable.apply(setProperties("r1", ["common.x": .int(99)]))

        #expect(editable.dirtyLayoutNodeIDs.contains("r1"))
    }

    // MARK: - Codable

    @Test("setProperties round-trips through JSON")
    func codableRoundTrip() throws {
        let op = setProperties("r1", [
            "kind.fills": .string("blue"),
            "kind.width": .int(200),
            "common.name": .null,
            "kind.effects": .array([.dictionary(["type": .string("blur")])]),
        ])

        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)

        #expect(decoded == op)
    }
}
