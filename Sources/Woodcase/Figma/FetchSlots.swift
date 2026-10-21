//
//  FetchSlots.swift
//  Woodcase
//

import Foundation

/// A counting semaphore for async work: at most `limit` holders at once, the rest waiting
/// in arrival order, a waiter's task cancelable while it waits.
actor FetchSlots {
    /// How many may hold a slot at once.
    let limit: Int
    /// How many hold one now.
    private var held = 0
    /// Those waiting for one, first come first served.
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    /// Slots for at most `limit` holders; a limit below one means one.
    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Takes a slot, waiting for one if all are held.
    ///
    /// - Throws: `CancellationError` when the task is canceled before it gets one; it then
    ///   holds nothing and must not call ``release()``.
    func acquire() async throws {
        try Task.checkCancellation()
        if held < limit {
            held += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enqueue(id, continuation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Queues a waiter, or wakes it with a cancellation at once if its task already is
    /// canceled. The cancellation handler's wake-up hops onto this actor, so it runs after
    /// this and finds the waiter queued.
    private func enqueue(_ id: UUID, _ continuation: CheckedContinuation<Void, any Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            waiters.append((id, continuation))
        }
    }

    /// Gives a slot back, handing it straight to the longest waiter if there is one.
    func release() {
        if waiters.isEmpty {
            held -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    /// Wakes the waiter `id` with a cancellation, if it is still waiting.
    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
