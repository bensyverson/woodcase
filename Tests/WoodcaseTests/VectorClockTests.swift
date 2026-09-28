//
//  VectorClockTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct VectorClockTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    @Test("increment advances peer's entry")
    func increment() {
        var vc = VectorClock()
        vc.increment(for: peerA)
        #expect(vc.time(for: peerA) == 1)

        vc.increment(for: peerA)
        #expect(vc.time(for: peerA) == 2)

        vc.increment(for: peerB)
        #expect(vc.time(for: peerB) == 1)
        #expect(vc.time(for: peerA) == 2)
    }

    @Test("dominates: strictly greater or equal in all entries")
    func dominatesTrue() {
        var vc1 = VectorClock()
        vc1.increment(for: peerA)
        vc1.increment(for: peerA)
        vc1.increment(for: peerB)

        var vc2 = VectorClock()
        vc2.increment(for: peerA)
        vc2.increment(for: peerB)

        #expect(vc1.dominates(vc2) == true)
    }

    @Test("dominates false when other has higher entry")
    func dominatesFalse() {
        var vc1 = VectorClock()
        vc1.increment(for: peerA)

        var vc2 = VectorClock()
        vc2.increment(for: peerB)

        #expect(vc1.dominates(vc2) == false)
    }

    @Test("concurrent: neither dominates the other")
    func concurrent() {
        var vc1 = VectorClock()
        vc1.increment(for: peerA)

        var vc2 = VectorClock()
        vc2.increment(for: peerB)

        #expect(vc1.dominates(vc2) == false)
        #expect(vc2.dominates(vc1) == false)
    }

    @Test("merge produces component-wise max")
    func merge() {
        var vc1 = VectorClock()
        vc1.increment(for: peerA) // A:1
        vc1.increment(for: peerA) // A:2

        var vc2 = VectorClock()
        vc2.increment(for: peerA) // A:1
        vc2.increment(for: peerB) // B:1
        vc2.increment(for: peerC) // C:1

        vc1.merge(vc2)
        #expect(vc1.time(for: peerA) == 2) // max(2, 1)
        #expect(vc1.time(for: peerB) == 1) // max(0, 1)
        #expect(vc1.time(for: peerC) == 1) // max(0, 1)
    }

    @Test("empty clock dominates empty clock")
    func emptyDominatesEmpty() {
        let vc1 = VectorClock()
        let vc2 = VectorClock()
        #expect(vc1.dominates(vc2) == true)
    }

    @Test("VectorClock is Friendly")
    func isFriendly() throws {
        var vc = VectorClock()
        vc.increment(for: peerA)
        vc.increment(for: peerB)

        let data = try JSONEncoder().encode(vc)
        let decoded = try JSONDecoder().decode(VectorClock.self, from: data)
        #expect(decoded == vc)
    }
}
