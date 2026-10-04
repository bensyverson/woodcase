//
//  ChangeCoordinatorConcurrencyTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Synchronization
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Pins ``ChangeCoordinator`` when two changes for one file are in flight at once — the
/// watcher's report and an adoption's announcement can overlap. Both must publish; one
/// waiting forever for a match the other already took would leave a task alive until the
/// server stops.
@Suite(.hangGuard)
struct ChangeCoordinatorConcurrencyTests {
    @Test("Two overlapping changes for one file both finish")
    func overlappingChangesBothFinish() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let coordinator = ChangeCoordinator(
            context: ViewerFixtures.context(files: [file], home: scratch),
            matchWindow: .milliseconds(200),
            pollInterval: .milliseconds(10)
        )

        let finished = Mutex(0)
        let first = Task {
            await coordinator.fileChanged(file)
            finished.withLock { $0 += 1 }
        }
        let second = Task {
            await coordinator.fileChanged(file)
            finished.withLock { $0 += 1 }
        }
        defer {
            first.cancel()
            second.cancel()
        }

        await waitUntil("both changes to publish") { finished.withLock { $0 } == 2 }
    }
}
