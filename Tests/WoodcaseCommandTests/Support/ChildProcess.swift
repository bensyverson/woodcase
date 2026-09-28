//
//  ChildProcess.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A long-running `woodcase` process a test launches, and is answerable for.
///
/// Most command tests run the binary to completion — ``CommandFixture/run(_:environment:)``
/// does that, and needs nothing else. This is for the other shape: a verb that does not
/// end on its own, such as `activity --follow`, which a test starts, observes, and must
/// take down again.
///
/// Two rules make that reliable, and both exist because breaking either one cost this
/// project whole test runs:
///
/// - **Never `waitUntilExit()`.** It is unbounded. A child that ignores the signal, or a
///   reap that does not land, turns a two-second test into a run that sits at 0 % CPU
///   until somebody notices. ``waitForExit(within:)`` polls against a deadline instead,
///   so the worst case is a recorded failure, not a hang.
/// - **Never leave the child behind.** An orphaned `woodcase` keeps polling and keeps a
///   lock-holding neighbour's file busy; the failure lands in whichever *later* test
///   touches that file, which is as far from the cause as a failure can get.
///   ``withChild(_:arguments:environment:standardOutput:_:)`` stops the child however the
///   body ends, and ``deinit`` is the backstop that `SIGKILL`s one that got past that.
final class ChildProcess: @unchecked Sendable {
    /// How often ``waitForExit(within:)`` re-checks.
    static let pollInterval: Duration = .milliseconds(20)

    /// How long a stopped child is given to go away before the next, harder step.
    static let stopBudget: Duration = .seconds(10)

    /// The launched process.
    let process: Process

    /// How the process was invoked, for a failure message.
    let invocation: String

    /// Launches the binary with the given arguments.
    ///
    /// - Parameters:
    ///   - binary: The `woodcase` executable to run.
    ///   - arguments: The command line, without the program name.
    ///   - environment: The whole environment for the run.
    ///   - standardOutput: A file to write the run's stdout into. Standard error is
    ///     discarded; a test that needs it should redirect it to a file of its own.
    /// - Throws: Whatever `Process` throws if the binary cannot be launched, or
    ///   `FileHandle` throws if `standardOutput` cannot be opened for writing.
    init(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        standardOutput: URL
    ) throws {
        process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment
        FileManager.default.createFile(atPath: standardOutput.path, contents: nil)
        process.standardOutput = try FileHandle(forWritingTo: standardOutput)
        process.standardError = FileHandle.nullDevice
        invocation = ([binary.lastPathComponent] + arguments).joined(separator: " ")
        try process.run()
    }

    deinit {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        FileHandle.standardError.write(Data(
            "ChildProcess: killed a surviving `\(invocation)` in deinit.\n".utf8
        ))
    }

    /// Whether the process is still alive.
    var isRunning: Bool {
        process.isRunning
    }

    /// Waits for the process to exit, giving up after `bound`.
    ///
    /// - Parameter bound: How long to keep checking.
    /// - Returns: `true` if the process exited inside the bound.
    func waitForExit(within bound: Duration = stopBudget) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: bound)
        while ContinuousClock.now < deadline {
            if !process.isRunning { return true }
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                break
            }
        }
        return !process.isRunning
    }

    /// Stops the process and does not return until it is gone.
    ///
    /// `SIGTERM` first, then `SIGKILL` if that was ignored. Either escalation is a
    /// recorded failure: a `woodcase` verb that does not stop when asked is the bug
    /// this class exists to catch, and silently killing it would hide it.
    ///
    /// - Parameter bound: How long each of the two steps is given.
    func stop(within bound: Duration = stopBudget) async {
        guard process.isRunning else { return }
        process.terminate()
        if await waitForExit(within: bound) { return }

        Issue.record("`\(invocation)` ignored SIGTERM for \(bound); sending SIGKILL.")
        kill(process.processIdentifier, SIGKILL)
        if await waitForExit(within: bound) { return }
        Issue.record("`\(invocation)` survived SIGKILL — pid \(process.processIdentifier) is leaked.")
    }

    /// Runs `body` with a live child, and stops the child however `body` ends.
    ///
    /// - Parameters:
    ///   - binary: The `woodcase` executable to run.
    ///   - arguments: The command line, without the program name.
    ///   - environment: The whole environment for the run.
    ///   - standardOutput: A file to write the run's stdout into.
    ///   - body: What to do while the child runs.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever launching the child, or `body`, throws.
    static func withChild<T>(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        standardOutput: URL,
        _ body: (ChildProcess) async throws -> T
    ) async throws -> T {
        let child = try ChildProcess(
            binary: binary,
            arguments: arguments,
            environment: environment,
            standardOutput: standardOutput
        )
        do {
            let value = try await body(child)
            await child.stop()
            return value
        } catch {
            await child.stop()
            throw error
        }
    }
}
