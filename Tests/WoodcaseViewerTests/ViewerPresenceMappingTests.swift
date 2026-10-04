//
//  ViewerPresenceMappingTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Pins the viewer's presence payload: mapping the library's ``Presence`` must produce
/// exactly the bytes the viewer's own tracker did.
struct ViewerPresenceMappingTests {
    private func event(_ identity: String, at seconds: TimeInterval, file: String) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: seconds),
            identity: identity,
            file: URL(fileURLWithPath: file),
            op: .set,
            nodes: ["A"],
            revision: "r"
        )
    }

    @Test("The payload is byte-identical to one built from the same tallies directly")
    func payloadIsByteIdentical() throws {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10, file: "/tmp/a.pen"))
        tracker.record(event("ben", at: 20, file: "/tmp/b.pen"))
        tracker.record(event("ana", at: 30, file: "/tmp/b.pen"))
        tracker.record(event("ana", at: 5, file: "/tmp/unserved.pen"))

        let ids = [
            ActivityEvent.canonicalPath(for: URL(fileURLWithPath: "/tmp/a.pen")): "aaa",
            ActivityEvent.canonicalPath(for: URL(fileURLWithPath: "/tmp/b.pen")): "bbb",
        ]
        let mapped = ViewerPresence(tracker.snapshot(), fileID: { ids[$0] })

        let expected = ViewerPresence(identities: [
            ViewerPresence.Identity(
                name: "ana", lastSeen: Date(timeIntervalSince1970: 30), events: 3, files: ["bbb", "aaa"]
            ),
            ViewerPresence.Identity(
                name: "ben", lastSeen: Date(timeIntervalSince1970: 20), events: 1, files: ["bbb"]
            ),
        ])
        #expect(try ViewerJSON.encoder.encode(mapped) == ViewerJSON.encoder.encode(expected))
    }

    @Test("An empty snapshot maps to an empty payload")
    func emptyMapsToEmpty() {
        #expect(ViewerPresence(Presence(), fileID: { _ in nil }).identities.isEmpty)
    }
}
