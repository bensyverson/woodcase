//
//  FollowerRecorder.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Runs a ``PenFileFollower`` in a task of its own and keeps everything it yields, so a
/// test can wait on what arrived rather than on a clock.
///
/// ```swift
/// let recorder = FollowerRecorder(follower)
/// defer { recorder.cancel() }
/// try write()
/// let change = await recorder.first { $0.change?.isAttributed == true }
/// ```
actor FollowerRecorder {
    /// Starts following.
    ///
    /// - Parameter follower: The follower to run.
    init(_ follower: PenFileFollower) {
        let box = Events()
        events = box
        task = Task {
            for await event in follower {
                await box.append(event)
            }
        }
    }

    /// The consuming task, which ends when canceled.
    nonisolated let task: Task<Void, Never>

    /// Everything yielded so far, in order.
    var received: [PenFileFollower.Event] {
        get async { await events.all }
    }

    /// Stops following.
    nonisolated func cancel() {
        task.cancel()
    }

    /// Waits for an event that matches, among those not yet consumed by an earlier wait.
    ///
    /// - Parameters:
    ///   - what: What is being waited for, for the failure message.
    ///   - matches: The test for the event.
    /// - Returns: The first match, or `nil` (and a recorded issue) after a minute.
    func next(
        _ what: Comment,
        where matches: @Sendable (PenFileFollower.Event) -> Bool
    ) async -> PenFileFollower.Event? {
        let deadline = ContinuousClock.now + .seconds(60)
        while true {
            let all = await events.all
            if let index = all[consumed...].firstIndex(where: matches) {
                consumed = index + 1
                return all[index]
            }
            guard ContinuousClock.now < deadline else { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("timed out waiting for \(what)")
        return nil
    }

    // MARK: - Private

    /// How many received events earlier waits have stepped past.
    private var consumed = 0

    private let events: Events

    /// The received events, appended from the consuming task.
    private actor Events {
        private(set) var all: [PenFileFollower.Event] = []

        func append(_ event: PenFileFollower.Event) {
            all.append(event)
        }
    }
}
