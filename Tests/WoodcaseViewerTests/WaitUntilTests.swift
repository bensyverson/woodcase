//
//  WaitUntilTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing

/// Exercises ``waitUntil(_:within:poll:_:)`` itself — the helper every viewer test
/// waits through.
///
/// It is worth its own suite because its failure mode is invisible: a wait that gives
/// up without looking one last time reports a timeout the code under test did not
/// earn, and the report names the *watcher* or the *hub*, never the wait.
@Suite("waitUntil", .hangGuard)
struct WaitUntilTests {
    @Test("A condition that already holds is never reported as a timeout, even with the bound spent")
    func alreadyTrueHoldsAtASpentBound() async {
        let held = await waitUntil("a condition that is already true", within: .zero) { true }
        #expect(held)
    }

    @Test("A condition that comes true while polling is held")
    func becomesTrueWhilePolling() async {
        let flag = LateFlag(after: 2)
        let held = await waitUntil(
            "the flag to be raised", within: .seconds(60), poll: .milliseconds(10)
        ) { await flag.raised() }
        #expect(held)
    }

    @Test("A condition that never holds is reported as a timeout rather than passing quietly")
    func neverTrueIsReported() async {
        var held: Bool?
        await withKnownIssue("the wait is meant to time out here") {
            held = await waitUntil(
                "a condition that never holds", within: .milliseconds(100), poll: .milliseconds(10)
            ) { false }
        }
        #expect(held == false)
    }
}

/// A condition that answers `false` a fixed number of times and `true` after that,
/// so a test can prove the wait polls rather than checking once.
private actor LateFlag {
    /// Creates a flag that stays down for `after` reads.
    init(after: Int) {
        remaining = after
    }

    /// How many more reads answer `false`.
    private var remaining: Int

    /// Whether the flag is up, counting this read.
    func raised() -> Bool {
        guard remaining > 0 else { return true }
        remaining -= 1
        return false
    }
}
