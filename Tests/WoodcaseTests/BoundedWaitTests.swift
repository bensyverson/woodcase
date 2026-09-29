//
//  BoundedWaitTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing

/// Exercises ``BoundedWait`` itself — the deadline every wait on a feed goes through.
///
/// The cases that matter are the ones where the job *never* answers and ignores
/// cancellation, because that is the shape of a completion handler that is never
/// called: a wait that cancels its job and then waits for it to notice hangs exactly as
/// long as the job does.
@Suite("BoundedWait", .hangGuard)
struct BoundedWaitTests {
    @Test("A job that finishes inside its budget hands back its value")
    func finishedJobReturnsItsValue() async throws {
        let value: Int = try await BoundedWait.value(within: .seconds(60)) { 42 }
        #expect(value == 42)
    }

    @Test("A job's own error is what the wait throws")
    func jobErrorPropagates() async {
        await #expect(throws: Refusal.self) {
            try await BoundedWait.value(within: .seconds(60)) { () throws -> Int in throw Refusal() }
        }
    }

    @Test("A job that never resumes and ignores cancellation is abandoned at its deadline")
    func unresumedJobExpires() async {
        let error = await #expect(throws: BoundedWait.Expired.self) {
            try await BoundedWait.value("a callback nobody calls", within: .milliseconds(200)) {
                await Parked.forever()
            }
        }
        #expect(error?.description.contains("a callback nobody calls") == true)
    }

    @Test("Canceling the waiter ends the wait even while its job ignores cancellation")
    func cancelingTheWaiterEndsTheWait() async {
        let waiter = Task {
            try await BoundedWait.value(within: .seconds(600)) { await Parked.forever() }
        }
        waiter.cancel()
        let outcome: Result<Int, any Error> = await waiter.result
        #expect(throws: CancellationError.self) { try outcome.get() }
    }

    @Test("A waiter canceled before it starts waiting still ends")
    func alreadyCanceledWaiterEnds() async {
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BoundedWait.value(within: .seconds(600)) { await Parked.forever() }
        }
        let outcome: Result<Int, any Error> = await waiter.result
        #expect(throws: CancellationError.self) { try outcome.get() }
    }
}

/// A thrown error the test can recognize by type.
private struct Refusal: Error {}

/// A job that suspends on a continuation nobody ever resumes, and does not listen for
/// cancellation — the shape of a completion handler that is never called.
private enum Parked {
    /// The continuations parked so far, kept alive so none is reported as leaked.
    private static let kept = Mutex<[CheckedContinuation<Int, Never>]>([])

    /// Suspends forever.
    static func forever() async -> Int {
        await withCheckedContinuation { continuation in
            kept.withLock { $0.append(continuation) }
        }
    }
}
