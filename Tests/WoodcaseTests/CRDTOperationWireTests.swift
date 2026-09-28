//
//  CRDTOperationWireTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Wire-readiness tests for CRDTOperation serialization.
///
/// These tests go beyond the simple round-trip tests in ``CRDTOperationTests``
/// by exercising complex node payloads, deterministic output, and the full
/// encode → Data → decode path that operations will traverse on the network.
struct CRDTOperationWireTests {
    private let peerA = PeerID(rawValue: "peerA")
    private let peerB = PeerID(rawValue: "peerB")

    private func makeOp(_ payload: CRDTOperation.Payload, time: UInt64 = 1) -> CRDTOperation {
        CRDTOperation(
            id: Timestamp(time: time, peerID: peerA),
            dependencies: VectorClock(),
            payload: payload
        )
    }

    private func wireRoundTrip(_ op: CRDTOperation) throws -> CRDTOperation {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(op)
        return try decoder.decode(CRDTOperation.self, from: data)
    }

    // MARK: - Complex CreateNode payloads

    @Test("CreateNode with frame + nested children round-trips")
    func createNodeFrameWithChildren() throws {
        let textChild = PenNode(
            id: "txt01",
            common: PenNodeCommon(name: "Label", opacity: .literal(0.8)),
            kind: .text(PenNode.TextData(
                width: .fitContent(fallback: nil),
                content: .literal("Hello world"),
                fontFamily: .literal("Inter"),
                fontSize: .literal(16)
            ))
        )
        let rectChild = PenNode(
            id: "rct01",
            common: PenNodeCommon(name: "Background"),
            kind: .rectangle(PenNode.RectangleData(
                width: .fillContainer(fallback: nil),
                height: .fixed(48),
                cornerRadius: .uniform(.literal(8)),
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let frame = PenNode(
            id: "frm01",
            common: PenNodeCommon(name: "Card", x: .literal(10), y: .literal(20)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(320),
                height: .fitContent(fallback: nil),
                layout: .vertical,
                gap: .literal(8),
                padding: .uniform(.literal(16)),
                children: [textChild, rectChild]
            ))
        )

        let op = makeOp(.createNode(CRDTOperation.CreateNode(node: frame, parentID: nil)))
        let decoded = try wireRoundTrip(op)

        guard case let .createNode(p) = decoded.payload else {
            Issue.record("Expected createNode")
            return
        }
        #expect(p.node.id == "frm01")
        #expect(p.node.common.name == "Card")
        #expect(p.parentID == nil)

        // Verify nested children survived
        guard case let .frame(data) = p.node.kind else {
            Issue.record("Expected frame kind")
            return
        }
        #expect(data.children?.count == 2)
        #expect(data.children?[0].id == "txt01")
        #expect(data.children?[1].id == "rct01")

        // Verify deeply nested properties
        guard case let .text(textData) = data.children?[0].kind else {
            Issue.record("Expected text kind")
            return
        }
        #expect(textData.fontFamily == .literal("Inter"))
        #expect(textData.fontSize == .literal(16))
    }

    @Test("CreateNode with ref + overrides round-trips")
    func createNodeRefWithOverrides() throws {
        let descendantOverride = PenDescendantOverride(properties: [
            "name": .string("Custom Label"),
            "fill": .array([.dictionary(["type": .string("solid"), "color": .string("#00FF00")])]),
        ])
        let ref = PenNode(
            id: "ref01",
            common: PenNodeCommon(name: "Button Instance"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: ["txt01": descendantOverride],
                rootOverrides: [
                    "width": .int(200),
                    "cornerRadius": .int(12),
                ]
            ))
        )

        let op = makeOp(.createNode(CRDTOperation.CreateNode(node: ref, parentID: "frm01")))
        let decoded = try wireRoundTrip(op)

        guard case let .createNode(p) = decoded.payload else {
            Issue.record("Expected createNode")
            return
        }
        #expect(p.node.id == "ref01")
        #expect(p.parentID == "frm01")

        guard case let .ref(refData) = p.node.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.ref == "comp1")
        #expect(refData.descendants?["txt01"] != nil)
        #expect(refData.rootOverrides?["width"] != nil)
        #expect(refData.rootOverrides?["cornerRadius"] != nil)
    }

    @Test("CreateNode with unknown node type round-trips")
    func createNodeUnknownType() throws {
        let unknown = PenNode(
            id: "unk01",
            common: PenNodeCommon(name: "Future Widget"),
            kind: .unknown(typeName: "hologram", properties: [
                "intensity": .double(0.75),
                "layers": .array([.int(1), .int(2), .int(3)]),
                "config": .dictionary(["nested": .bool(true)]),
            ])
        )

        let op = makeOp(.createNode(CRDTOperation.CreateNode(node: unknown, parentID: nil)))
        let decoded = try wireRoundTrip(op)

        guard case let .createNode(p) = decoded.payload else {
            Issue.record("Expected createNode")
            return
        }
        #expect(p.node.id == "unk01")
        #expect(p.node.common.name == "Future Widget")

        guard case let .unknown(typeName, properties) = p.node.kind else {
            Issue.record("Expected unknown kind")
            return
        }
        #expect(typeName == "hologram")
        #expect(properties["intensity"] != nil)
        #expect(properties["layers"] != nil)
        #expect(properties["config"] != nil)
    }

    // MARK: - Deterministic JSON output

    @Test("All payload types produce deterministic JSON with sortedKeys")
    func deterministicJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let payloads: [CRDTOperation.Payload] = [
            .setProperty(CRDTOperation.SetProperty(
                nodeID: "n1", property: "common.name", value: .string("Test")
            )),
            .listInsert(CRDTOperation.ListInsert(
                listID: "__root__", elementID: "c1",
                afterPositionID: nil,
                positionTimestamp: Timestamp(time: 1, peerID: peerA)
            )),
            .listDelete(CRDTOperation.ListDelete(
                listID: "p1",
                positionID: PositionID(timestamp: Timestamp(time: 1, peerID: peerA))
            )),
            .listMove(CRDTOperation.ListMove(
                sourceListID: "p1", targetListID: "p2",
                positionID: PositionID(timestamp: Timestamp(time: 1, peerID: peerA)),
                afterPositionID: nil,
                newPositionTimestamp: Timestamp(time: 2, peerID: peerA)
            )),
            .treeMove(CRDTOperation.TreeMove(nodeID: "n1", newParentID: "n2")),
            .createNode(CRDTOperation.CreateNode(
                node: PenNode(
                    id: "n1",
                    common: PenNodeCommon(name: "R"),
                    kind: .rectangle(PenNode.RectangleData(width: .fixed(50)))
                ),
                parentID: nil
            )),
            .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")),
            .setVariable(CRDTOperation.SetVariable(
                name: "v1",
                variable: PenVariable(type: .color, value: .simple(.string("#000")))
            )),
            .removeVariable(CRDTOperation.RemoveVariable(name: "v1")),
            .setImport(CRDTOperation.SetImport(alias: "icons", path: "./icons.pen")),
            .removeImport(CRDTOperation.RemoveImport(alias: "icons")),
            .setThemeAxis(CRDTOperation.SetThemeAxis(name: "mode", options: ["light", "dark"])),
            .removeThemeAxis(CRDTOperation.RemoveThemeAxis(name: "mode")),
        ]

        for payload in payloads {
            let op = makeOp(payload)
            let data1 = try encoder.encode(op)
            let data2 = try encoder.encode(op)
            #expect(data1 == data2, "Non-deterministic JSON for \(payload)")
        }
    }

    // MARK: - Full wire path

    @Test("Full operation encode → Data → decode round-trips with id and dependencies")
    func fullWirePathRoundTrip() throws {
        var deps = VectorClock()
        deps.entries[peerA] = 5
        deps.entries[peerB] = 3

        let op = CRDTOperation(
            id: Timestamp(time: 6, peerID: peerA),
            dependencies: deps,
            payload: .setProperty(CRDTOperation.SetProperty(
                nodeID: "node1",
                property: "kind.width",
                value: .int(320)
            ))
        )

        let decoded = try wireRoundTrip(op)

        #expect(decoded.id == op.id)
        #expect(decoded.dependencies == deps)
        #expect(decoded.id.time == 6)
        #expect(decoded.id.peerID == peerA)
        #expect(decoded.dependencies.time(for: peerA) == 5)
        #expect(decoded.dependencies.time(for: peerB) == 3)

        guard case let .setProperty(p) = decoded.payload else {
            Issue.record("Expected setProperty")
            return
        }
        #expect(p.nodeID == "node1")
        #expect(p.property == "kind.width")
    }

    // MARK: - OperationLog serialization

    @Test("OperationLog round-trips through JSON")
    func operationLogRoundTrip() throws {
        var log = OperationLog(peerID: peerA)
        log.appendLocal(payload: .setProperty(CRDTOperation.SetProperty(
            nodeID: "n1", property: "common.name", value: .string("Hello")
        )))
        log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n2")))

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .setVariable(CRDTOperation.SetVariable(
                name: "color",
                variable: PenVariable(type: .color, value: .simple(.string("#FFF")))
            ))
        )
        log.appendRemote(remoteOp)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(log)
        let decoded = try decoder.decode(OperationLog.self, from: data)

        #expect(decoded.peerID == peerA)
        #expect(decoded.operations.count == 3)
        #expect(decoded.vectorClock.time(for: peerA) == 2)
        // The remote op had empty dependencies, so the vector clock won't have peerB.
        // But the Lamport clock advances past the remote op's time.
        #expect(decoded.clock.time >= 10)

        // Verify individual operations survived
        guard case .setProperty = decoded.operations[0].payload else {
            Issue.record("Expected setProperty at index 0")
            return
        }
        guard case .deleteNode = decoded.operations[1].payload else {
            Issue.record("Expected deleteNode at index 1")
            return
        }
        guard case .setVariable = decoded.operations[2].payload else {
            Issue.record("Expected setVariable at index 2")
            return
        }
    }
}
