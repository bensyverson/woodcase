//
//  LWWRegisterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct LWWRegisterTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    @Test("Higher timestamp wins")
    func higherTimestampWins() {
        var reg = LWWRegister(value: "old", timestamp: Timestamp(time: 1, peerID: peerA))
        let accepted = reg.set("new", at: Timestamp(time: 2, peerID: peerA))
        #expect(accepted == true)
        #expect(reg.value == "new")
    }

    @Test("Stale write is rejected")
    func staleWriteRejected() {
        var reg = LWWRegister(value: "current", timestamp: Timestamp(time: 5, peerID: peerA))
        let accepted = reg.set("stale", at: Timestamp(time: 3, peerID: peerA))
        #expect(accepted == false)
        #expect(reg.value == "current")
    }

    @Test("Tie-breaking: same time, higher peerID wins")
    func tieBreakByPeerID() {
        var reg = LWWRegister(value: "fromA", timestamp: Timestamp(time: 5, peerID: peerA))
        let accepted = reg.set("fromB", at: Timestamp(time: 5, peerID: peerB))
        #expect(accepted == true)
        #expect(reg.value == "fromB") // peerB > peerA
    }

    @Test("Equal timestamp: no change (idempotent)")
    func equalTimestampIdempotent() {
        var reg = LWWRegister(value: "value", timestamp: Timestamp(time: 5, peerID: peerA))
        let accepted = reg.set("other", at: Timestamp(time: 5, peerID: peerA))
        #expect(accepted == false)
        #expect(reg.value == "value")
    }

    @Test("Convergence: two registers set in opposite orders converge")
    func convergence() {
        let ts1 = Timestamp(time: 1, peerID: peerA)
        let ts2 = Timestamp(time: 2, peerID: peerB)

        // Register 1: sees ts1 first, then ts2
        var reg1 = LWWRegister(value: "a", timestamp: ts1)
        reg1.set("b", at: ts2)

        // Register 2: sees ts2 first, then ts1
        var reg2 = LWWRegister(value: "b", timestamp: ts2)
        reg2.set("a", at: ts1)

        #expect(reg1.value == reg2.value)
        #expect(reg1.timestamp == reg2.timestamp)
    }

    @Test("LWWRegister is Friendly")
    func isFriendly() throws {
        let reg = LWWRegister(value: "test", timestamp: Timestamp(time: 1, peerID: peerA))
        let data = try JSONEncoder().encode(reg)
        let decoded: LWWRegister<String> = try JSONDecoder().decode(LWWRegister<String>.self, from: data)
        #expect(decoded == reg)
    }
}
