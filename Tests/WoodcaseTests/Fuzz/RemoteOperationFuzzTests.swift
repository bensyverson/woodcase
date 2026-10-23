//
//  RemoteOperationFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Hostile and malformed remote operations: none may trap or hang a replica, and one
/// the boundary refuses must leave the document exactly as it was (leaf Ol1s6D).
///
/// A trap would end the test process, so finishing is the "never traps" assertion.
@MainActor
struct RemoteOperationFuzzTests {
    private static let local = PeerID(rawValue: "local")
    private static let peers = [local, PeerID(rawValue: "remote"), PeerID(rawValue: ""), PeerID(rawValue: "zzzz")]

    private static let times: [UInt64] = [
        0, 1, 2, 3, 50, .max, .max - 1, 1 << 63, LamportClock.ceiling, LamportClock.ceiling + 1,
        LamportClock.maximumLead, LamportClock.maximumLead + 2,
    ]

    private static let ids = [
        "r1", "r2", "t1", "t2", "g1", "f1", "f2", "r3", "e1", "btn", "inst1",
        "", "__root__", "new", "loop", String(repeating: "x", count: 4096),
    ]

    private static let junkPaths = [
        "", ".", "kind.", "common.", "common.name.extra", "kind.children", "extras",
        "metadata.woodcase.", "kind.fill.99999999999999999999", "kind.width.-1", "common.theme.",
    ]

    private static var values: [AnyCodable] {
        var deep = AnyCodable.array([])
        for _ in 0 ..< 200 {
            deep = .array([deep])
        }
        return [
            .null, .bool(true), .int(.max), .int(.min), .int(-1), .int(0),
            .double(1e308), .double(-1e308), .double(-0.0), .double(5e-324),
            .string(""), .string(String(repeating: "é", count: 10000)), .string("$missing"),
            .array([]), .array([.int(.max), .null]), deep,
            .dictionary([:]), .dictionary(["": .null, "type": .string("frame"), "id": .int(.min)]),
        ]
    }

    @Test("Hostile remote operations never trap, never cycle the tree, and a refused one changes nothing",
          arguments: 0 ..< 8)
    func hostileOperations(seed: UInt64) throws {
        var rng = SeededRandomNumberGenerator(seed: seed &+ 0x5AFE)
        let editable = EditableDocument(from: FuzzFixture.document(), peerID: Self.local)
        let crdt = try #require(editable.crdtDocument)

        for step in 0 ..< 300 {
            let operation = randomOperation(in: editable, rng: &rng)
            let before = RemoteInputState(editable)
            let verdict: RemoteInputError?
            do {
                try crdt.validateRemote(operation)
                verdict = nil
            } catch {
                verdict = error
            }

            let refused = editable.applyRemote(operation)

            #expect(refused == verdict, "seed \(seed) step \(step)")
            if verdict != nil {
                #expect(RemoteInputState(editable) == before, "seed \(seed) step \(step): a refused operation changed the document")
            }
            #expect(RemoteInputState.parentCycle(in: editable) == nil, "seed \(seed) step \(step): parent cycle")
            #expect(crdt.operationLog.clock.time <= LamportClock.ceiling + UInt64(step) + 1)
        }

        // The replica still edits: no clock was pushed to where the next tick traps.
        if let nodeID = editable.nodes.keys.sorted().first {
            _ = try? editable.applyLocal(.updateCommon(.init(nodeID: nodeID, common: PenNodeCommon(name: "After"))))
        }
        #expect(RemoteInputState.parentCycle(in: editable) == nil)
    }

    // MARK: - Generation

    private func randomOperation(in document: EditableDocument, rng: inout SeededRandomNumberGenerator) -> CRDTOperation {
        CRDTOperation(
            id: timestamp(&rng),
            dependencies: dependencies(&rng),
            payload: payload(in: document, rng: &rng)
        )
    }

    private func timestamp(_ rng: inout SeededRandomNumberGenerator) -> Timestamp {
        let time = Bool.random(using: &rng) ? Self.times.randomElement(using: &rng)! : UInt64.random(in: 0 ... 1000, using: &rng)
        return Timestamp(time: time, peerID: Self.peers.randomElement(using: &rng)!)
    }

    private func dependencies(_ rng: inout SeededRandomNumberGenerator) -> VectorClock {
        var clock = VectorClock()
        for peer in Self.peers where Int.random(in: 0 ..< 3, using: &rng) == 0 {
            clock.entries[peer] = Self.times.randomElement(using: &rng)!
        }
        return clock
    }

    private func id(_ rng: inout SeededRandomNumberGenerator) -> String {
        Self.ids.randomElement(using: &rng)!
    }

    private func position(_ rng: inout SeededRandomNumberGenerator) -> PositionID? {
        Bool.random(using: &rng) ? nil : PositionID(timestamp: timestamp(&rng))
    }

    private func payload(in document: EditableDocument, rng: inout SeededRandomNumberGenerator) -> CRDTOperation.Payload {
        switch Int.random(in: 0 ..< 13, using: &rng) {
        case 0:
            let nodeID = id(&rng)
            var paths = Self.junkPaths
            if let node = document.nodes[nodeID] {
                paths += NodePropertyCodec.paths(for: node)
            }
            return .setProperty(.init(nodeID: nodeID, property: paths.randomElement(using: &rng)!, value: Self.values.randomElement(using: &rng)!))
        case 1:
            return .listInsert(.init(listID: id(&rng), elementID: id(&rng), afterPositionID: position(&rng), positionTimestamp: timestamp(&rng)))
        case 2:
            return .listDelete(.init(listID: id(&rng), positionID: PositionID(timestamp: timestamp(&rng))))
        case 3:
            return .listMove(.init(
                sourceListID: id(&rng), targetListID: id(&rng), positionID: PositionID(timestamp: timestamp(&rng)),
                afterPositionID: position(&rng), newPositionTimestamp: timestamp(&rng)
            ))
        case 4:
            return .treeMove(.init(nodeID: id(&rng), newParentID: Bool.random(using: &rng) ? nil : id(&rng)))
        case 5:
            let template = document.nodes.values.sorted { $0.id < $1.id }.randomElement(using: &rng)
            let kind = template?.kind ?? .frame(PenNode.FrameData())
            let node = PenNode(id: id(&rng), common: PenNodeCommon(name: "Fuzz"), kind: kind)
            return .createNode(.init(node: node, parentID: Bool.random(using: &rng) ? node.id : id(&rng)))
        case 6:
            return .deleteNode(.init(nodeID: id(&rng)))
        case 7:
            return .setVariable(.init(name: id(&rng), variable: PenVariable(type: .number, value: .simple(Self.values.randomElement(using: &rng)!))))
        case 8:
            return .removeVariable(.init(name: id(&rng)))
        case 9:
            return .setImport(.init(alias: id(&rng), path: id(&rng)))
        case 10:
            return .removeImport(.init(alias: id(&rng)))
        case 11:
            return .setThemeAxis(.init(name: id(&rng), options: [id(&rng), id(&rng)]))
        default:
            return .removeThemeAxis(.init(name: id(&rng)))
        }
    }
}
