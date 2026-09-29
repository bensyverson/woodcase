//
//  ResumeOnce.swift
//  WoodcaseViewer
//

import Dispatch
import Foundation
import Synchronization

/// A continuation resumed exactly once, by whichever gets there first: the callback, a
/// second callback, or the deadline that fires when no callback ever does.
///
/// ## Why the viewer needs this
///
/// Network.framework answers in callbacks, and a callback that never arrives leaves a
/// `withCheckedContinuation` suspended for the life of the process. That failure is
/// invisible: a Swift task suspended at an `await` has no thread and therefore no stack,
/// so a `sample` of the wedged process contains no frame of ours to explain itself — the
/// signature is the *absence* of a signature. Every await the viewer makes on a socket
/// goes through here, so no state handler and no send completion can suspend it
/// indefinitely, however Network.framework behaves.
///
/// ```swift
/// let delivered: Bool = await ResumeOnce.value(
///     within: .seconds(30), on: queue, expiring: { connection.cancel(); return false }
/// ) { box in
///     connection.send(content: data, completion: .contentProcessed { box.resume(with: $0 == nil) })
/// }
/// ```
///
/// ## Exactly once, not at most once
///
/// Resuming a checked continuation twice is a crash, and Network.framework does answer
/// twice — a listener reports `.ready` and later `.cancelled`, a send completes after the
/// deadline already gave up on it. The box takes the continuation and its expiry together
/// under one lock, so the first answer wins, every later one is dropped, and the expiry's
/// side effect runs only when the deadline is what resumed. A connection is therefore
/// never canceled out from under a callback that already succeeded, and an ordinary
/// write — of which the viewer makes thousands — lets go of its connection the instant it
/// completes rather than at the end of the budget.
@available(macOS 15, iOS 18, *)
final class ResumeOnce<Value: Sendable>: Sendable {
    /// How long the viewer waits on a Network.framework callback by default.
    ///
    /// A *not hung* guard rather than a measurement: binding a loopback port or handing
    /// a few kilobytes to the transport takes milliseconds, and this is sized far past
    /// anything the parallel suite's load can explain, per `project/gotchas.md`.
    static var budget: Duration {
        .seconds(30)
    }

    /// Awaits a Network.framework callback that cannot be allowed to never arrive.
    ///
    /// - Parameters:
    ///   - budget: How long to wait for `arming`'s callback.
    ///   - queue: The queue the deadline is armed on.
    ///   - expiring: Produces the value to resume with when the budget is spent, and is
    ///     the place to cancel whatever was being waited on. It runs only if the deadline
    ///     is what resumes the continuation, and is released as soon as anything does.
    ///   - arming: Starts the work, handing it the box to resume.
    /// - Returns: The callback's value, or `expiring`'s.
    static func value(
        within budget: Duration,
        on queue: DispatchQueue,
        expiring: @escaping @Sendable () -> Value,
        arming: @escaping @Sendable (ResumeOnce<Value>) -> Void
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let box = ResumeOnce(continuation, expiring: expiring)
            queue.asyncAfter(deadline: .now() + budget.seconds) { box.expire() }
            arming(box)
        }
    }

    /// Wraps a continuation and the answer to give if nothing else answers.
    ///
    /// - Parameters:
    ///   - continuation: The continuation to resume exactly once.
    ///   - expiring: What to resume with once the budget is spent.
    init(
        _ continuation: CheckedContinuation<Value, Never>,
        expiring: @escaping @Sendable () -> Value
    ) {
        pending = Mutex(Pending(continuation: continuation, expiring: expiring))
    }

    /// Resumes with a value, or does nothing if something else already resumed.
    ///
    /// - Parameter value: What to hand back to the awaiting task.
    func resume(with value: Value) {
        take()?.continuation.resume(returning: value)
    }

    // MARK: - Private

    /// A continuation and its unused fallback, taken together or not at all.
    private struct Pending {
        /// The task waiting for an answer.
        let continuation: CheckedContinuation<Value, Never>
        /// The answer the deadline gives, and the side effect it runs getting there.
        let expiring: @Sendable () -> Value
    }

    /// What has not been resumed yet.
    private let pending: Mutex<Pending?>

    /// Resumes with the fallback, unless a callback got there first.
    private func expire() {
        guard let taken = take() else { return }
        taken.continuation.resume(returning: taken.expiring())
    }

    /// Claims the right to resume, exactly once.
    private func take() -> Pending? {
        pending.withLock { held in
            defer { held = nil }
            return held
        }
    }
}

@available(macOS 15, iOS 18, *)
private extension Duration {
    /// The duration as seconds, for a Dispatch deadline.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
