//
//  TimestampTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct TimestampTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - PeerID

    @Test("PeerID generate produces unique IDs")
    func peerIDGenerate() {
        let id1 = PeerID.generate()
        let id2 = PeerID.generate()
        #expect(id1 != id2)
    }

    @Test("PeerID Comparable is lexicographic")
    func peerIDComparable() {
        #expect(peerA < peerB)
    }

    @Test("PeerID is Friendly")
    func peerIDFriendly() throws {
        let id = PeerID.generate()
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(PeerID.self, from: data)
        #expect(decoded == id)
    }

    // MARK: - Timestamp

    @Test("Different times: lower time is less")
    func differentTimes() {
        let t1 = Timestamp(time: 1, peerID: peerB)
        let t2 = Timestamp(time: 2, peerID: peerA)
        #expect(t1 < t2)
    }

    @Test("Same time: lower peerID is less")
    func sameTimeDifferentPeers() {
        let t1 = Timestamp(time: 5, peerID: peerA)
        let t2 = Timestamp(time: 5, peerID: peerB)
        #expect(t1 < t2)
    }

    @Test("Equal timestamps are equal")
    func equalTimestamps() {
        let t1 = Timestamp(time: 3, peerID: peerA)
        let t2 = Timestamp(time: 3, peerID: peerA)
        #expect(t1 == t2)
        #expect(!(t1 < t2))
        #expect(!(t2 < t1))
    }

    @Test("Timestamp is Friendly")
    func timestampFriendly() throws {
        let ts = Timestamp(time: 42, peerID: peerA)
        let data = try JSONEncoder().encode(ts)
        let decoded = try JSONDecoder().decode(Timestamp.self, from: data)
        #expect(decoded == ts)
    }
}
