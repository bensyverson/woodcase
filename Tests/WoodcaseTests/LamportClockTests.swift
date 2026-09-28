//
//  LamportClockTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct LamportClockTests {
    @Test("tick increments the clock")
    func tickIncrements() {
        var clock = LamportClock()
        #expect(clock.time == 0)

        let t1 = clock.tick()
        #expect(t1 == 1)
        #expect(clock.time == 1)

        let t2 = clock.tick()
        #expect(t2 == 2)
        #expect(clock.time == 2)
    }

    @Test("witness updates to max(local, remote) + 1")
    func witnessHigherValue() {
        var clock = LamportClock()
        _ = clock.tick() // time = 1

        clock.witness(10)
        #expect(clock.time == 11)
    }

    @Test("witness with lower value still increments")
    func witnessLowerValue() {
        var clock = LamportClock()
        _ = clock.tick() // time = 1
        _ = clock.tick() // time = 2
        _ = clock.tick() // time = 3

        clock.witness(1)
        #expect(clock.time == 4) // max(3, 1) + 1
    }

    @Test("Lamport clock is Friendly")
    func isFriendly() throws {
        var clock = LamportClock()
        _ = clock.tick()

        let data = try JSONEncoder().encode(clock)
        let decoded = try JSONDecoder().decode(LamportClock.self, from: data)
        #expect(decoded == clock)
    }
}
