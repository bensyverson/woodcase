//
//  DocumentSessionPlaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A position change logs ``ActivityEvent/Kind/place``, never `mv`: an agent reading the
/// log must not mistake a nudge or a freeform drag for a reparent.
struct DocumentSessionPlaceTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let file = URL(fileURLWithPath: "/tmp/session-place.pen")

    private func makeSession() -> DocumentSession {
        DocumentSession(
            document: SessionTestDocuments.make().materialize(),
            author: ana,
            file: file,
            collaborative: false
        )
    }

    private func position(_ nodeID: String, x: Double, y: Double) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.x": .double(x), "common.y": .double(y)]))
    }

    @Test("each operation is labeled: a position-only write is place; rotation, or position beside another property, is set")
    func positionLogsPlace() throws {
        let session = makeSession()
        let rotate = EditOperation.setProperties(EditOperation.SetProperties(nodeID: "c2", properties: ["common.rotation": 45]))
        let moveAndRename = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "c3", properties: ["common.x": 5, "common.name": "Moved"]
        ))
        let change = try session.submit(.local(LocalEdit(operations: [position("c1", x: 10, y: 20), rotate, moveAndRename])))
        #expect(change.activity.map(\.op) == [.place, .set, .set])

        let line = try String(decoding: #require(change.activity.first).jsonLine(), as: UTF8.self)
        #expect(line.contains(#""op":"place""#))
        #expect(try ActivityEvent(line: Data(line.utf8)).op == .place)
    }

    @Test("a whole-struct update that only moves the node is normalized, then logs place")
    func wholeStructPositionLogsPlace() throws {
        let session = makeSession()
        var common = try #require(session.document.nodes["c1"]).common
        common.x = .literal(42)
        let change = try session.submit(.local(LocalEdit(operations: [.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common))])))
        #expect(change.activity.map(\.op) == [.place])
    }

    @Test("a reparent still logs mv, beside a placement in the same edit")
    func reparentStillLogsMv() throws {
        let session = makeSession()
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))
        let change = try session.submit(.local(LocalEdit(operations: [move, position("c2", x: 0, y: 0)])))
        #expect(change.activity.map(\.op) == [.mv, .place])

        // Supplied explicitly, place labels what would otherwise derive set.
        let resize = EditOperation.setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["kind.width": 10]))
        let labeled = try session.submit(.local(LocalEdit(operations: [resize, position("c1", x: 1, y: 1)], activityKind: .place)))
        #expect(labeled.activity.map(\.op) == [.place, .place])
    }
}
