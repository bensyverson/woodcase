//
//  FontRegistryGateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The two properties ``FontRegistryGate`` exists for.
///
/// Exclusion is the point — one thread inside Core Text's font registry at a time —
/// and reentrancy is what makes it usable, because the gated calls nest: resolving a
/// font asks whether its family is available, and both go through the gate. A
/// non-recursive lock there would not be slow, it would deadlock.
struct FontRegistryGateTests {
    /// The high-water mark of threads simultaneously inside the gate.
    private final class Occupancy: @unchecked Sendable {
        private(set) var current = 0
        private(set) var peak = 0

        func enter() {
            current += 1
            peak = max(peak, current)
        }

        func leave() {
            current -= 1
        }
    }

    @Test("The gate lets one thread in at a time")
    func admitsOneThreadAtATime() {
        let occupancy = Occupancy()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            FontRegistryGate.withAccess {
                occupancy.enter()
                // Long enough that an unguarded body would certainly overlap.
                Thread.sleep(forTimeInterval: 0.002)
                occupancy.leave()
            }
        }

        #expect(occupancy.peak == 1)
        #expect(occupancy.current == 0)
    }

    @Test("The gate is reentrant, because the calls it guards nest")
    func admitsANestedCall() {
        let value = FontRegistryGate.withAccess {
            FontRegistryGate.withAccess { 7 }
        }

        #expect(value == 7)
    }

    @Test("A throwing body releases the gate")
    func releasesOnThrow() {
        struct Failure: Error {}

        #expect(throws: Failure.self) {
            try FontRegistryGate.withAccess { throw Failure() }
        }
        // If the gate were still held, this would never return.
        #expect(FontRegistryGate.withAccess { true })
    }
}
