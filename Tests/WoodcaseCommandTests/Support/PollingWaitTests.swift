//
//  PollingWaitTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing

/// ``PollingWait`` looks once more after its deadline.
///
/// `followStopsWhenOrphaned` used to poll with a loop that tested its deadline before
/// the condition and never after: a sleep that resumed past the deadline ended the
/// wait without looking, so a follower that had exited during that sleep was reported
/// as one that never did. Under the parallel suite a test's sleep can resume seconds
/// late (issue `jBvokK`).
@Suite("Polling wait")
struct PollingWaitTests {
    @Test("A condition that came true while the waiter slept past its deadline is seen")
    func looksAfterTheDeadline() async {
        let bound: Duration = .milliseconds(100)
        // True from the wait's own deadline on — so only a look made after it can see it.
        let turnsTrue = ContinuousClock.now + bound
        let outcome = await PollingWait(bound: bound, poll: .seconds(1)).until {
            ContinuousClock.now >= turnsTrue
        }
        #expect(outcome.satisfied, "\(outcome.summary)")
    }

    @Test("A condition that already holds is seen on the first look")
    func seesAHoldingConditionAtOnce() async {
        let outcome = await PollingWait(bound: .seconds(30), poll: .seconds(30)).until { true }
        #expect(outcome.satisfied)
        #expect(outcome.looks == 1)
    }

    @Test("A condition that never holds is reported unsatisfied, with every look counted")
    func reportsAConditionThatNeverHolds() async {
        let outcome = await PollingWait(bound: .milliseconds(200), poll: .milliseconds(20)).until { false }
        #expect(!outcome.satisfied)
        #expect(outcome.looks >= 2)
        #expect(outcome.elapsed >= .milliseconds(200))
        #expect(outcome.longestGap >= .milliseconds(20))
    }
}
