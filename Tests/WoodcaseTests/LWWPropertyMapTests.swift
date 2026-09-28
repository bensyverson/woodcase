//
//  LWWPropertyMapTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct LWWPropertyMapTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    @Test("Accept newer timestamp for a property")
    func acceptNewer() {
        var map = LWWPropertyMap()
        map.record(property: "common.name", at: Timestamp(time: 1, peerID: peerA))

        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 2, peerID: peerA)) == true)
    }

    @Test("Reject older timestamp for a property")
    func rejectOlder() {
        var map = LWWPropertyMap()
        map.record(property: "common.name", at: Timestamp(time: 5, peerID: peerA))

        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 3, peerID: peerA)) == false)
    }

    @Test("Independent properties don't interfere")
    func independentProperties() {
        var map = LWWPropertyMap()
        map.record(property: "common.name", at: Timestamp(time: 10, peerID: peerA))
        map.record(property: "common.opacity", at: Timestamp(time: 1, peerID: peerA))

        // name has high timestamp, but opacity has low — an update to opacity at time 5 should be accepted
        #expect(map.shouldAccept(property: "common.opacity", at: Timestamp(time: 5, peerID: peerA)) == true)
        // but update to name at time 5 should be rejected
        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 5, peerID: peerA)) == false)
    }

    @Test("Unseen property is always accepted")
    func unseenProperty() {
        let map = LWWPropertyMap()
        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 1, peerID: peerA)) == true)
    }

    @Test("Tie-breaking by peerID")
    func tieBreakByPeerID() {
        var map = LWWPropertyMap()
        map.record(property: "common.name", at: Timestamp(time: 5, peerID: peerA))

        // Same time, higher peerID should win
        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 5, peerID: peerB)) == true)
        // Same time, lower peerID should lose
        #expect(map.shouldAccept(property: "common.name", at: Timestamp(time: 5, peerID: peerA)) == false)
    }

    @Test("LWWPropertyMap is Friendly")
    func isFriendly() throws {
        var map = LWWPropertyMap()
        map.record(property: "common.name", at: Timestamp(time: 1, peerID: peerA))

        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(LWWPropertyMap.self, from: data)
        #expect(decoded == map)
    }
}
