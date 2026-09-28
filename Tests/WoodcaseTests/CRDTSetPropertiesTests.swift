//
//  CRDTSetPropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTSetPropertiesTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Helpers

    private func makeRectDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(50)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect]))
        )
        return PenDocument(children: [frame])
    }

    private func makePair() -> (EditableDocument, EditableDocument) {
        let doc = makeRectDoc()
        return (EditableDocument(from: doc, peerID: peerA), EditableDocument(from: doc, peerID: peerB))
    }

    private func setProperties(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    // MARK: - Criterion 3: one LWW write per path, and two peers converge

    @Test("The CRDT emits exactly one setProperty op per path")
    func oneWritePerPath() throws {
        let (a, _) = makePair()

        let ops = try a.applyLocal(setProperties("r1", [
            "kind.fills": .string("blue"),
            "kind.width": .int(300),
            "common.name": .string("Renamed"),
        ]))

        let setProps = ops.compactMap { op -> CRDTOperation.SetProperty? in
            if case let .setProperty(p) = op.payload { return p }
            return nil
        }
        #expect(ops.count == 3)
        #expect(Set(setProps.map(\.property)) == ["kind.fills", "kind.width", "common.name"])
        #expect(setProps.allSatisfy { $0.nodeID == "r1" })
    }

    @Test("Each emitted path is recorded in the node's LWW property map")
    func pathsRecordedInPropertyMap() throws {
        let (a, _) = makePair()
        _ = try a.applyLocal(setProperties("r1", ["kind.fills": .string("blue")]))

        let map = try #require(a.crdtDocument?.propertyMaps["r1"])
        #expect(map.timestamps["kind.fills"] != nil)
        #expect(map.timestamps["kind.width"] == nil)
    }

    @Test("A setProperties patch converges on a second peer")
    func patchConverges() throws {
        let (a, b) = makePair()

        let ops = try a.applyLocal(setProperties("r1", [
            "kind.fills": .string("blue"),
            "common.name": .string("Renamed"),
        ]))
        b.applyRemote(ops)

        #expect(a.nodes["r1"] == b.nodes["r1"])
        guard case let .rectangle(data) = b.nodes["r1"]?.kind else {
            Issue.record("Expected rectangle on peer B")
            return
        }
        #expect(data.fills == .single(.shorthand("blue")))
        #expect(data.width == .fixed(100))
        #expect(b.nodes["r1"]?.common.name == "Renamed")
    }

    @Test("Concurrent patches to different paths both survive")
    func concurrentDisjointPathsMerge() throws {
        let (a, b) = makePair()

        let opsA = try a.applyLocal(setProperties("r1", ["kind.fills": .string("blue")]))
        let opsB = try b.applyLocal(setProperties("r1", ["kind.width": .int(300)]))

        b.applyRemote(opsA)
        a.applyRemote(opsB)

        #expect(a.nodes["r1"] == b.nodes["r1"])
        guard case let .rectangle(data) = a.nodes["r1"]?.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.fills == .single(.shorthand("blue")))
        #expect(data.width == .fixed(300))
    }

    @Test("Concurrent patches to the same path converge on one winner")
    func concurrentSamePathConverges() throws {
        let (a, b) = makePair()

        let opsA = try a.applyLocal(setProperties("r1", ["kind.width": .int(200)]))
        let opsB = try b.applyLocal(setProperties("r1", ["kind.width": .int(300)]))

        b.applyRemote(opsA)
        a.applyRemote(opsB)

        #expect(a.nodes["r1"] == b.nodes["r1"])
    }

    @Test("A patch that clears a property converges as a clear")
    func clearConverges() throws {
        let (a, b) = makePair()

        let ops = try a.applyLocal(setProperties("r1", ["common.name": .null]))
        b.applyRemote(ops)

        #expect(b.nodes["r1"]?.common.name == nil)
        #expect(a.nodes["r1"] == b.nodes["r1"])
    }

    @Test("A property a replica has never seen still converges on an unknown node type")
    func unknownNodeTypeGainsNewProperty() throws {
        let node = PenNode(
            id: "u1",
            common: PenNodeCommon(name: "Sparkle"),
            kind: .unknown(typeName: "sparkle", properties: ["glow": .int(3)])
        )
        let doc = PenDocument(children: [node])
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)

        let ops = try a.applyLocal(setProperties("u1", ["kind.shimmer": .int(7)]))
        b.applyRemote(ops)

        #expect(a.nodes["u1"] == b.nodes["u1"])
        guard case let .unknown(_, properties) = b.nodes["u1"]?.kind else {
            Issue.record("Expected unknown kind on peer B")
            return
        }
        #expect(properties == ["glow": .int(3), "shimmer": .int(7)])
    }

    /// The shared ``NodePropertyCodec`` also serves ``EditOperation/updateKind(_:)``'s
    /// replication, and an unknown node type is where a strict vocabulary would have
    /// silently dropped a remote write.
    @Test("updateKind on an unknown node type converges through the shared codec")
    func updateKindOnUnknownTypeConverges() throws {
        let node = PenNode(
            id: "u1",
            common: PenNodeCommon(name: "Sparkle"),
            kind: .unknown(typeName: "sparkle", properties: ["glow": .int(3)])
        )
        let doc = PenDocument(children: [node])
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)

        let ops = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "u1",
            kind: .unknown(typeName: "sparkle", properties: ["glow": .int(3), "shimmer": .int(7)])
        )))
        b.applyRemote(ops)

        #expect(a.nodes["u1"] == b.nodes["u1"])
    }

    @Test("A rejected patch emits no CRDT operations and mutates neither peer")
    func rejectedPatchEmitsNothing() {
        let (a, b) = makePair()
        let before = a.nodes["r1"]

        #expect(throws: EditingError.self) {
            _ = try a.applyLocal(self.setProperties("r1", [
                "kind.width": .int(300),
                "kind.fontSize": .int(14),
            ]))
        }

        #expect(a.nodes["r1"] == before)
        #expect(b.nodes["r1"] == before)
    }
}
