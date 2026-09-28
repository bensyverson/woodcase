//
//  CRDTOperationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct CRDTOperationTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let peerA = PeerID(rawValue: "aaa")

    private func roundTrip(_ op: CRDTOperation) throws -> CRDTOperation {
        let data = try encoder.encode(op)
        return try decoder.decode(CRDTOperation.self, from: data)
    }

    private func makeOp(_ payload: CRDTOperation.Payload) -> CRDTOperation {
        CRDTOperation(
            id: Timestamp(time: 1, peerID: peerA),
            dependencies: VectorClock(),
            payload: payload
        )
    }

    // MARK: - Round-trip serialization of every payload case

    @Test("setProperty round-trip")
    func setPropertyRoundTrip() throws {
        let op = makeOp(.setProperty(CRDTOperation.SetProperty(
            nodeID: "n1",
            property: "common.name",
            value: AnyCodable("Hello")
        )))
        let decoded = try roundTrip(op)
        if case let .setProperty(p) = decoded.payload {
            #expect(p.nodeID == "n1")
            #expect(p.property == "common.name")
        } else {
            Issue.record("Expected setProperty")
        }
    }

    @Test("listInsert round-trip")
    func listInsertRoundTrip() throws {
        let op = makeOp(.listInsert(CRDTOperation.ListInsert(
            listID: "__root__",
            elementID: "child1",
            afterPositionID: nil,
            positionTimestamp: Timestamp(time: 1, peerID: peerA)
        )))
        let decoded = try roundTrip(op)
        if case let .listInsert(p) = decoded.payload {
            #expect(p.listID == "__root__")
            #expect(p.elementID == "child1")
            #expect(p.afterPositionID == nil)
        } else {
            Issue.record("Expected listInsert")
        }
    }

    @Test("listDelete round-trip")
    func listDeleteRoundTrip() throws {
        let op = makeOp(.listDelete(CRDTOperation.ListDelete(
            listID: "parent1",
            positionID: PositionID(timestamp: Timestamp(time: 1, peerID: peerA))
        )))
        let decoded = try roundTrip(op)
        if case let .listDelete(p) = decoded.payload {
            #expect(p.listID == "parent1")
        } else {
            Issue.record("Expected listDelete")
        }
    }

    @Test("listMove round-trip")
    func listMoveRoundTrip() throws {
        let op = makeOp(.listMove(CRDTOperation.ListMove(
            sourceListID: "parent1",
            targetListID: "parent2",
            positionID: PositionID(timestamp: Timestamp(time: 1, peerID: peerA)),
            afterPositionID: nil,
            newPositionTimestamp: Timestamp(time: 2, peerID: peerA)
        )))
        let decoded = try roundTrip(op)
        if case let .listMove(p) = decoded.payload {
            #expect(p.sourceListID == "parent1")
            #expect(p.targetListID == "parent2")
        } else {
            Issue.record("Expected listMove")
        }
    }

    @Test("treeMove round-trip")
    func treeMoveRoundTrip() throws {
        let op = makeOp(.treeMove(CRDTOperation.TreeMove(
            nodeID: "n1",
            newParentID: "n2"
        )))
        let decoded = try roundTrip(op)
        if case let .treeMove(p) = decoded.payload {
            #expect(p.nodeID == "n1")
            #expect(p.newParentID == "n2")
        } else {
            Issue.record("Expected treeMove")
        }
    }

    @Test("createNode round-trip")
    func createNodeRoundTrip() throws {
        let node = PenNode(
            id: "new1",
            common: PenNodeCommon(name: "Test"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let op = makeOp(.createNode(CRDTOperation.CreateNode(
            node: node,
            parentID: "parent1"
        )))
        let decoded = try roundTrip(op)
        if case let .createNode(p) = decoded.payload {
            #expect(p.node.id == "new1")
            #expect(p.parentID == "parent1")
        } else {
            Issue.record("Expected createNode")
        }
    }

    @Test("deleteNode round-trip")
    func deleteNodeRoundTrip() throws {
        let op = makeOp(.deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")))
        let decoded = try roundTrip(op)
        if case let .deleteNode(p) = decoded.payload {
            #expect(p.nodeID == "n1")
        } else {
            Issue.record("Expected deleteNode")
        }
    }

    @Test("setVariable round-trip")
    func setVariableRoundTrip() throws {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#FF0000")))
        let op = makeOp(.setVariable(CRDTOperation.SetVariable(name: "primary", variable: variable)))
        let decoded = try roundTrip(op)
        if case let .setVariable(p) = decoded.payload {
            #expect(p.name == "primary")
            #expect(p.variable.type == .color)
        } else {
            Issue.record("Expected setVariable")
        }
    }

    @Test("removeVariable round-trip")
    func removeVariableRoundTrip() throws {
        let op = makeOp(.removeVariable(CRDTOperation.RemoveVariable(name: "unused")))
        let decoded = try roundTrip(op)
        if case let .removeVariable(p) = decoded.payload {
            #expect(p.name == "unused")
        } else {
            Issue.record("Expected removeVariable")
        }
    }

    @Test("setImport round-trip")
    func setImportRoundTrip() throws {
        let op = makeOp(.setImport(CRDTOperation.SetImport(alias: "icons", path: "./icons.pen")))
        let decoded = try roundTrip(op)
        if case let .setImport(p) = decoded.payload {
            #expect(p.alias == "icons")
            #expect(p.path == "./icons.pen")
        } else {
            Issue.record("Expected setImport")
        }
    }

    @Test("removeImport round-trip")
    func removeImportRoundTrip() throws {
        let op = makeOp(.removeImport(CRDTOperation.RemoveImport(alias: "icons")))
        let decoded = try roundTrip(op)
        if case let .removeImport(p) = decoded.payload {
            #expect(p.alias == "icons")
        } else {
            Issue.record("Expected removeImport")
        }
    }

    @Test("setThemeAxis round-trip")
    func setThemeAxisRoundTrip() throws {
        let op = makeOp(.setThemeAxis(CRDTOperation.SetThemeAxis(name: "mode", options: ["light", "dark"])))
        let decoded = try roundTrip(op)
        if case let .setThemeAxis(p) = decoded.payload {
            #expect(p.name == "mode")
            #expect(p.options == ["light", "dark"])
        } else {
            Issue.record("Expected setThemeAxis")
        }
    }

    @Test("removeThemeAxis round-trip")
    func removeThemeAxisRoundTrip() throws {
        let op = makeOp(.removeThemeAxis(CRDTOperation.RemoveThemeAxis(name: "mode")))
        let decoded = try roundTrip(op)
        if case let .removeThemeAxis(p) = decoded.payload {
            #expect(p.name == "mode")
        } else {
            Issue.record("Expected removeThemeAxis")
        }
    }
}
