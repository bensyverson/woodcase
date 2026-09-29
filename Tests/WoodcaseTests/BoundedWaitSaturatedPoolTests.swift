//
//  BoundedWaitSaturatedPoolTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// ``BoundedWait``'s deadline fires on time while every thread of Swift's cooperative
/// pool is busy.
///
/// A "not hung" guard is needed most on a saturated machine. When its timer was a pool
/// task, a full-suite run saw `sleep 20` under a one-second deadline come back as a
/// normal exit after 74 s (`SwiftUIRenderBatchRunAsyncTests`, 2026-09-28): neither the
/// timer nor the job could get a thread, and the job got one first.
@Suite("BoundedWait on a saturated pool", .hangGuard)
struct BoundedWaitSaturatedPoolTests {
    /// How long the pool is held. Long against the deadline, short against the suite.
    private static let hold: TimeInterval = 1.0

    /// Holds the calling thread until `release` is signaled, then passes the signal on;
    /// never longer than ``failsafe``, so the test cannot wedge the run.
    ///
    /// Blocking a pool thread is exactly what async code must never do, and exactly what
    /// this test needs, so the wait sits in a synchronous function of its own.
    private static func block(until release: DispatchSemaphore) {
        _ = release.wait(timeout: .now() + failsafe)
        release.signal()
    }

    /// The longest a blocker holds its thread, whatever happens to the release.
    private static let failsafe: TimeInterval = 5

    @Test("The deadline wins over a job that cannot get a pool thread until after it")
    func deadlineFiresWhileThePoolIsBlocked() async {
        // Occupy every pool thread with a synchronous wait the pool cannot preempt. Held
        // tasks are queued ahead of the job and the timer below, so neither can start
        // until the hold ends.
        let release = DispatchSemaphore(value: 0)
        let width = ProcessInfo.processInfo.activeProcessorCount
        let blockers = (0 ..< width).map { _ in
            Task.detached {
                Self.block(until: release)
            }
        }
        // A thread of its own, so the release depends on neither the pool nor Dispatch.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: Self.hold)
            release.signal()
        }

        await #expect(throws: BoundedWait.Expired.self) {
            try await BoundedWait.value("a job queued behind a blocked pool", within: .milliseconds(100)) { 42 }
        }
        for blocker in blockers {
            await blocker.value
        }
    }
}
