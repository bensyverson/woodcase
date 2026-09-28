//
//  SwiftUIRenderBatchRunAsyncTests.swift
//  WoodcaseTests
//

// macOS-only: exercises SwiftUIRenderBatch.runAsync, which shells out to Xcode's
// toolchain.
#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// Pins ``SwiftUIRenderBatch/runAsync(_:log:deadline:)``'s two outcomes directly,
    /// with `/bin/echo` and `/bin/sleep` standing in for a well-behaved and a hung
    /// `swiftc`: a process that exits on its own reports its real status, and one the
    /// deadline kills says so — naming the command, the deadline and how long it
    /// actually ran — rather than surfacing an empty message that reads like a silent
    /// pass or a broken emitter.
    @Suite("SwiftUIRenderBatch.runAsync")
    struct SwiftUIRenderBatchRunAsyncTests {
        /// A log file under the per-process scratch directory, unique to this call.
        private func freshLog() -> URL {
            TestOutputDirectory.url.appendingPathComponent("runAsync-\(UUID().uuidString.prefix(8)).log")
        }

        @Test("A process that exits on its own reports its status and output")
        func exitsNormally() async throws {
            let outcome = try await SwiftUIRenderBatch.runAsync(
                ["/bin/echo", "hello"], log: freshLog(), deadline: .seconds(30)
            )
            guard case let .exited(status, output, _) = outcome else {
                Issue.record("expected .exited, got \(outcome)")
                return
            }
            #expect(status == 0)
            #expect(outcome.status == 0)
            #expect(outcome.succeeded)
            #expect(output.contains("hello"))
        }

        @Test("A process that outruns its deadline is killed and reports it, not an empty message")
        func killedByDeadline() async throws {
            let outcome = try await SwiftUIRenderBatch.runAsync(
                ["/bin/sleep", "20"], log: freshLog(), deadline: .seconds(1)
            )
            guard case let .timedOut(command, deadline, elapsed, logged) = outcome else {
                Issue.record("expected .timedOut, got \(outcome)")
                return
            }
            #expect(command.contains("sleep"))
            #expect(deadline == .seconds(1))
            #expect(elapsed >= .seconds(1))
            // /bin/sleep never writes to its log, so the raw capture is empty — the
            // typed case still carries that faithfully.
            #expect(logged.isEmpty)

            #expect(outcome.status == nil)
            #expect(!outcome.succeeded)
            // The message a caller actually reports must never be empty, and must name
            // the deadline, the elapsed time, the command, and that the machine may be
            // loaded — this is the failure the batch reported as "" before this fix.
            #expect(!outcome.output.isEmpty)
            #expect(outcome.output.contains("sleep"))
            #expect(outcome.output.contains("killed after 1 s"))
            #expect(outcome.output.lowercased().contains("loaded"))
            #expect(outcome.output.contains("SwiftUIRenderTests"))
        }

        @Test("A killed child's message survives even when its log truly has nothing in it")
        func timeoutOutputNeverEmpty() async throws {
            let outcome = try await SwiftUIRenderBatch.runAsync(
                ["/bin/sleep", "20"], log: freshLog(), deadline: .milliseconds(300)
            )
            #expect(!outcome.output.isEmpty)
        }
    }

#endif
