//
//  BoundedWait.swift
//  WoodcaseTests
//

import Foundation
import Synchronization

/// Runs an async job with a deadline, so a test that waits on something that never
/// answers fails and names the job instead of wedging the whole run.
///
/// The suite's expensive failure is not a red test, it is a run that stops printing:
/// an `await` on a callback that never arrives — a feed that never delivers, a
/// fetch whose transfer stalls — suspends its task forever, and a suspended task has
/// no stack frames, so it does not even appear in a `sample` of the hung host. Every
/// wait on a live feed goes through here: **an `await` on a callback you do not own
/// needs a deadline you do.** A call into a headless page does not: SleepyHollow's
/// `PageHost` bounds every one itself (`PageHost.callBudget`).
///
/// ```swift
/// let seen = try await BoundedWait.value {
///     await firstTwoRevisions(of: reader.follow())
/// }
/// ```
///
/// ## What the budget is, and is not
///
/// It is a *not hung* guard, not a measurement. It is deliberately far longer than
/// anything being tested, because under the parallel suite a 10 ms sleep has been
/// observed to take twelve seconds to resume — a budget near the interval under test
/// would measure the machine's load and nothing else. Never assert on how long a job
/// took; assert on what it produced.
///
/// ## A job that ignores cancellation is abandoned, not awaited
///
/// The job runs in a task of its own, and the caller waits on a continuation that
/// whichever finishes first resumes: the job, the deadline, or the caller's own
/// cancellation. When the deadline wins, the job is cancelled *and then left behind* —
/// the caller does not wait for it to notice. That is the difference from a task group,
/// which cannot return until every child has, and so hangs with any child that never
/// resumes — a bridged completion handler never ends early on cancellation. Honouring the caller's
/// cancellation the same way is what lets a test's `.timeLimit` end a test that is
/// stuck here rather than only reporting it.
enum BoundedWait {
    /// How long a job may run before it is abandoned and the wait fails.
    static let budget: Duration = .seconds(30)

    /// The failure a job that outstays its budget reports.
    struct Expired: Error, CustomStringConvertible {
        /// What was being waited for, when the caller named it.
        let job: String?
        /// The budget the job outstayed.
        let budget: Duration

        /// A sentence naming the job and the budget, so the test output says what
        /// happened.
        var description: String {
            let what: String = job.map { "\($0) " } ?? "the job "
            return "\(what)did not finish within \(budget); it was abandoned rather than left to hang"
        }
    }

    /// Runs `work` and returns what it produced, or throws once the budget is spent.
    ///
    /// - Parameters:
    ///   - job: What is being waited for, named in ``Expired`` so a failure says which
    ///     await never answered.
    ///   - budget: How long `work` may run. Defaults to ``budget``.
    ///   - work: The job to run. It is cancelled when the budget is spent, and
    ///     abandoned whether or not it notices.
    /// - Returns: Whatever `work` returned.
    /// - Throws: ``Expired`` if the budget was spent first, `CancellationError` if the
    ///   caller was cancelled first, and anything `work` throws.
    static func value<T: Sendable>(
        _ job: String? = nil,
        within budget: Duration = budget,
        of work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = Race<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.arm(continuation)
                race.hold(Task {
                    do {
                        try await race.settle(.success(work()))
                    } catch {
                        race.settle(.failure(error))
                    }
                })
                race.hold(Task {
                    try? await Task.sleep(for: budget)
                    race.settle(.failure(Expired(job: job, budget: budget)))
                })
            }
        } onCancel: {
            race.settle(.failure(CancellationError()))
        }
    }

    /// One continuation, resumed by whichever of its racers settles first.
    ///
    /// A settle that arrives before the continuation is armed — the caller was already
    /// cancelled — is kept and delivered on arming, so no order of events can leave the
    /// continuation unresumed or resume it twice.
    private final class Race<T: Sendable>: Sendable {
        /// Where the race stands.
        private enum State {
            /// Neither armed nor settled.
            case idle
            /// Armed, waiting for the first racer.
            case armed(CheckedContinuation<T, any Error>)
            /// Settled before it was armed.
            case early(Result<T, any Error>)
            /// Resumed; every later settle is dropped.
            case done
        }

        /// The race's state and its racers, under one lock, so a racer held after the
        /// race is decided is cancelled rather than missed.
        private let books = Mutex<(state: State, racers: [Task<Void, Never>])>((.idle, []))

        /// Hands the race the continuation to resume.
        func arm(_ continuation: CheckedContinuation<T, any Error>) {
            let early: Result<T, any Error>? = books.withLock { books in
                switch books.state {
                case .idle:
                    books.state = .armed(continuation)
                    return nil
                case let .early(result):
                    books.state = .done
                    return result
                case .armed, .done:
                    return nil
                }
            }
            if let early {
                continuation.resume(with: early)
                cancelRacers()
            }
        }

        /// Settles the race with `result`, unless something settled it already.
        func settle(_ result: Result<T, any Error>) {
            let continuation: CheckedContinuation<T, any Error>? = books.withLock { books in
                switch books.state {
                case .idle:
                    books.state = .early(result)
                    return nil
                case let .armed(continuation):
                    books.state = .done
                    return continuation
                case .early, .done:
                    return nil
                }
            }
            guard let continuation else { return }
            continuation.resume(with: result)
            cancelRacers()
        }

        /// Keeps a racer so the race can cancel it once decided; cancels it at once if
        /// the race already is.
        func hold(_ racer: Task<Void, Never>) {
            let decided: Bool = books.withLock { books in
                if case .done = books.state { return true }
                books.racers.append(racer)
                return false
            }
            if decided {
                racer.cancel()
            }
        }

        /// Cancels every racer still running: the job, if it listens, and the timer.
        private func cancelRacers() {
            let held: [Task<Void, Never>] = books.withLock { books in
                defer { books.racers = [] }
                return books.racers
            }
            for racer in held {
                racer.cancel()
            }
        }
    }
}
