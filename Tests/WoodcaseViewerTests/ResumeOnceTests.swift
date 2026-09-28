//
//  ResumeOnceTests.swift
//  WoodcaseViewerTests
//

import Dispatch
import Foundation
import Testing
@testable import WoodcaseViewer

/// The guarantee the viewer's socket seam rests on: an awaited Network.framework
/// callback always resumes, even when the callback never comes.
@Suite("ResumeOnce", .hangGuard)
struct ResumeOnceTests {
    /// A queue of this suite's own, so an expiry timer never shares the server's.
    private static let queue = DispatchQueue(label: "dev.woodcase.tests.resume-once")

    @Test("the callback's own value comes back when it fires")
    func callbackWins() async {
        let value: Int = await ResumeOnce.value(
            within: .seconds(30), on: Self.queue, expiring: { -1 }
        ) { box in
            box.resume(with: 7)
        }
        #expect(value == 7)
    }

    /// The red test this seam exists for: a callback that never fires must produce a
    /// value within a bound rather than suspending the task forever. A suspended task
    /// has no thread and no stack, so the failure it used to cause was a whole test run
    /// stopped at 0 % CPU with nothing of ours in the sample to explain it.
    @Test("a callback that never fires expires instead of hanging")
    func deadlineWins() async {
        let value: Int = await ResumeOnce.value(
            within: .milliseconds(50), on: Self.queue, expiring: { -1 }
        ) { _ in
            // Exactly what a dead Network.framework state handler does: nothing.
        }
        #expect(value == -1)
    }

    @Test("the expiry's side effect runs when the deadline is what resumes")
    func deadlineRunsItsSideEffect() async {
        let cancelled = Signal()
        let value: Int = await ResumeOnce.value(
            within: .milliseconds(50), on: Self.queue,
            expiring: {
                cancelled.raise()
                return -1
            }
        ) { _ in }
        #expect(value == -1)
        #expect(cancelled.isRaised)
    }

    /// Network.framework may answer late — a `send` completion arrives after the
    /// connection is cancelled — and resuming a checked continuation twice is a crash,
    /// so the second answer has to be dropped rather than delivered.
    @Test("a callback that arrives after the deadline is ignored")
    func lateCallbackIsDropped() async {
        let late = Signal()
        let value: Int = await ResumeOnce.value(
            within: .milliseconds(50), on: Self.queue, expiring: { -1 }
        ) { box in
            Self.queue.asyncAfter(deadline: .now() + 0.4) {
                box.resume(with: 7)
                late.raise()
            }
        }
        #expect(value == -1)
        // Give the late callback time to land on a live continuation and crash the run.
        try? await Task.sleep(for: .milliseconds(600))
        #expect(late.isRaised)
    }

    /// An answered callback must *release* its expiry, not merely outrun it. The expiry
    /// holds the connection it would cancel, so a box that kept it until the budget
    /// elapsed would leave every one of the viewer's ordinary writes — thousands a run —
    /// pinning a finished connection for another thirty seconds.
    @Test("an answered callback lets go of its expiry at once")
    func answeringReleasesTheExpiry() async {
        let released = Signal()
        let value: Int = await Self.resumeImmediately(reporting: released)
        #expect(value == 7)
        #expect(released.isRaised)
    }

    /// Resumes through the box straight away, with an expiry holding an object whose
    /// release is the observation. The object is local to this call, so once it returns
    /// the only thing that can still be holding it is the box.
    private static func resumeImmediately(reporting released: Signal) async -> Int {
        let witness = Witness { released.raise() }
        return await ResumeOnce.value(
            within: .seconds(30), on: queue,
            expiring: { withExtendedLifetime(witness) { -1 } }
        ) { box in
            box.resume(with: 7)
        }
    }

    /// Reports its own deallocation, so a test can see what is still being held.
    private final class Witness: Sendable {
        init(_ released: @escaping @Sendable () -> Void) {
            self.released = released
        }

        deinit { released() }

        private let released: @Sendable () -> Void
    }

    @Test("only the first of many callbacks is delivered")
    func firstCallbackWins() async {
        let value: Int = await ResumeOnce.value(
            within: .seconds(30), on: Self.queue, expiring: { -1 }
        ) { box in
            box.resume(with: 1)
            box.resume(with: 2)
            box.resume(with: 3)
        }
        #expect(value == 1)
    }

    /// A one-way flag a callback on any queue can raise.
    private final class Signal: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false

        func raise() {
            lock.lock()
            raised = true
            lock.unlock()
        }

        var isRaised: Bool {
            lock.lock()
            defer { lock.unlock() }
            return raised
        }
    }
}
