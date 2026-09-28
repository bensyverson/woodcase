//
//  CommandFixture.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A temp directory holding a copy of a test fixture and its own `$WOODCASE_HOME`,
/// with the built `woodcase` binary pointed at it.
///
/// The house rule is that tests drive the binary: what an agent sees is stdout, stderr
/// and an exit status, and only a real process produces all three. Everything a run
/// touches is inside ``root``, which is deleted when the fixture goes out of scope, so
/// no test can reach this repository's own `.woodcase` or edit a fixture in it. Clearing
/// `WOODCASE_HOME` for a run — an empty value is ignored — is how a test exercises the
/// project-local default instead; see `ProjectLocalLogTests`.
///
/// ```swift
/// let fixture = try CommandFixture(fixture: "batch.pen")
/// let run = try fixture.run("migrate", "--dry-run", fixture.file.path)
/// #expect(run.status == 0)
/// ```
///
/// In-process `parse` tests remain the right tool for flags and option groups; reach
/// for this when the exit code, the stderr message or the stdout bytes are the subject.
final class CommandFixture: Sendable {
    /// Copies a fixture into a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - fixture: The file name inside `Tests/WoodcaseTests/Fixtures`,
    ///     for example `batch.pen`.
    ///   - editedOutsideWoodcase: Whether this test rewrites the .pen file behind the
    ///     log's back on purpose, which is the one way a run may legitimately print the
    ///     outside-write note. Every other fixture asserts it never appears — see
    ///     ``checkForOutsideWriteNote(_:arguments:)``.
    /// - Throws: Whatever `FileManager` throws if the directory cannot be made or the
    ///   fixture cannot be found and copied.
    init(fixture: String, editedOutsideWoodcase: Bool = false) throws {
        self.editedOutsideWoodcase = editedOutsideWoodcase
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandFixture-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("woodcase-home", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        file = try Self.copy(fixture: fixture, into: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// The temporary directory everything this fixture touches lives in.
    let root: URL

    /// The directory handed to the binary as `$WOODCASE_HOME`, so the activity log
    /// written by a run is this run's and nobody else's.
    let home: URL

    /// The copied fixture, safe to edit.
    let file: URL

    /// Whether this test rewrites the .pen file outside woodcase on purpose.
    let editedOutsideWoodcase: Bool

    /// The activity log a run of the binary appends to.
    var activityLog: URL {
        home.appendingPathComponent(ActivityLog.fileName)
    }

    /// Copies another fixture in beside the first.
    ///
    /// - Parameter fixture: The file name inside `Tests/WoodcaseTests/Fixtures`.
    /// - Returns: The copy's URL.
    /// - Throws: Whatever `FileManager` throws if the fixture cannot be found or copied.
    @discardableResult
    func copy(fixture: String) throws -> URL {
        try Self.copy(fixture: fixture, into: root)
    }

    /// Runs the built binary with the given arguments.
    ///
    /// - Parameters:
    ///   - arguments: The command line, without the program name.
    ///   - environment: Variables to add to — or override in — the run's environment.
    ///     `WOODCASE_HOME` and `HOME` already point inside ``root``.
    ///   - stdin: Bytes to write to the process's standard input, then close — for a
    ///     verb read with `-F -`. `nil` (the default) leaves standard input untouched.
    /// - Returns: What the process printed and the status it exited with.
    /// - Throws: ``CommandFixture/LaunchFailure`` if the binary cannot be found, or
    ///   whatever `Process` throws if it cannot be launched.
    func run(_ arguments: [String], environment: [String: String] = [:], stdin: Data? = nil) throws -> CommandRun {
        let binary = try Self.binary()
        let outURL = root.appendingPathComponent("stdout-\(UUID().uuidString).txt")
        let errURL = root.appendingPathComponent("stderr-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = self.environment(adding: environment)
        // Files rather than pipes: a pipe whose buffer fills deadlocks a process that
        // is still writing while we wait for it to exit.
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)
        let stdinPipe = stdin.map { _ in Pipe() }
        if let stdinPipe {
            process.standardInput = stdinPipe
        }
        try process.run()
        if let stdinPipe, let stdin {
            stdinPipe.fileHandleForWriting.write(stdin)
            try stdinPipe.fileHandleForWriting.close()
        }
        Self.waitForExit(of: process, arguments: arguments)

        let run = CommandRun(
            status: process.terminationStatus,
            stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        )
        checkForOutsideWriteNote(run, arguments: arguments)
        return run
    }

    /// The phrase the outside-write note is recognisable by, wherever it is printed.
    ///
    /// Not the whole sentence and not the bare `note  ` marker: the marker is shared
    /// with ``Woodcase/WriteDivergence``'s own notes, which are a normal part of a
    /// write's answer, and the whole sentence names a path that changes every run.
    static let outsideWriteNote = "was rewritten outside woodcase"

    /// Fails the test if a run reported an edit made outside woodcase.
    ///
    /// This is the standing proof that a file edited only through `woodcase` never
    /// produces the note: it runs on **every** command every fixture spawns, so a write
    /// path that leaves the activity log unable to account for the file fails whichever
    /// suite exercises it, not only the ones written for the note. The one fixture that
    /// rewrites its .pen file on purpose opts out with `editedOutsideWoodcase`.
    ///
    /// - Parameters:
    ///   - run: What the process printed.
    ///   - arguments: The command line, for the message.
    private func checkForOutsideWriteNote(_ run: CommandRun, arguments: [String]) {
        guard !editedOutsideWoodcase else { return }
        guard run.stdout.contains(Self.outsideWriteNote)
            || run.stderr.contains(Self.outsideWriteNote)
        else { return }
        Issue.record("""
        `woodcase \(arguments.joined(separator: " "))` reported that the file was rewritten \
        outside woodcase, but this fixture is only ever edited through the binary. Either a \
        write path is not recording what it did, or the test means to edit the file from \
        outside and should say so with `CommandFixture(fixture:editedOutsideWoodcase:)`.
        """)
    }

    /// Runs the built binary with the given arguments.
    ///
    /// - Parameter arguments: The command line, without the program name.
    /// - Returns: What the process printed and the status it exited with.
    /// - Throws: Whatever ``run(_:environment:)`` throws.
    func run(_ arguments: String...) throws -> CommandRun {
        try run(arguments)
    }

    /// Starts the binary without waiting for it to exit, for a verb like `serve` that
    /// only stops when it is signalled.
    ///
    /// - Parameters:
    ///   - arguments: The command line, without the program name.
    ///   - environment: Variables to add to — or override in — the run's environment.
    /// - Returns: A handle over the still-running process and its growing output.
    /// - Throws: ``LaunchFailure`` if the binary cannot be found, or whatever
    ///   `Process` throws if it cannot be launched.
    func runInBackground(_ arguments: [String], environment: [String: String] = [:]) throws -> LiveRun {
        let binary = try Self.binary()
        let outURL = root.appendingPathComponent("stdout-\(UUID().uuidString).txt")
        let errURL = root.appendingPathComponent("stderr-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = self.environment(adding: environment)
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)
        try process.run()
        return LiveRun(process: process, stdoutURL: outURL, stderrURL: errURL)
    }

    /// A still-running process started by ``runInBackground(_:environment:)``.
    ///
    /// For a verb — `serve`, so far the only one — whose success path never exits, so
    /// the ordinary blocking ``run(_:environment:)`` cannot observe it without waiting
    /// out its whole budget.
    struct LiveRun {
        /// The launched process.
        let process: Process
        /// Where its standard output is being collected.
        let stdoutURL: URL
        /// Where its standard error is being collected.
        let stderrURL: URL

        /// Waits for at least one line of stdout — `woodcase serve`'s flushed URL or
        /// JSON report, in particular — then returns it without its trailing newline.
        ///
        /// - Parameter timeout: How long to wait before giving up.
        /// - Returns: The first line, or `nil` if none arrived inside `timeout`.
        func firstLine(timeout: Duration = .seconds(10)) -> String? {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if let text = try? String(contentsOf: stdoutURL, encoding: .utf8),
                   let line = text.split(separator: "\n", maxSplits: 1).first,
                   !line.isEmpty
                {
                    return String(line)
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return nil
        }

        /// Everything written to standard error so far.
        var stderrText: String {
            (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        }

        /// Signals the process to stop, the way `Ctrl-C` does, and waits for it to exit.
        ///
        /// - Parameter timeout: How long to wait before escalating to `SIGKILL`.
        func stop(timeout: Duration = .seconds(10)) {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGINT)
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while process.isRunning, ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// How long one run of the binary may take before the fixture gives up on it.
    ///
    /// A verb that takes two minutes is broken; a fixture that waits for it forever
    /// turns one broken verb into a run that never ends and prints nothing, which is the
    /// shape that cost this project several multi-hour "hangs". `Process.waitUntilExit()`
    /// has no bound of its own, so the fixture polls against this one instead.
    static let runBudget: Duration = .seconds(120)

    /// Waits for a launched run to finish, killing it if it outstays ``runBudget``.
    ///
    /// - Parameters:
    ///   - process: The launched run.
    ///   - arguments: The command line, for the failure message.
    private static func waitForExit(of process: Process, arguments: [String]) {
        guard !waitForExit(of: process, within: runBudget) else { return }
        Issue.record(
            "`woodcase \(arguments.joined(separator: " "))` ran past \(runBudget); killing it."
        )
        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(of: process, within: .seconds(10))
    }

    /// Polls until the process exits or `bound` elapses.
    ///
    /// - Parameters:
    ///   - process: The launched run.
    ///   - bound: How long to keep checking.
    /// - Returns: `true` if the process exited inside the bound.
    private static func waitForExit(of process: Process, within bound: Duration) -> Bool {
        let deadline = ContinuousClock.now.advanced(by: bound)
        while process.isRunning, ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        return !process.isRunning
    }

    /// The binary could not be located or the fixture could not be found.
    enum LaunchFailure: Error, CustomStringConvertible {
        /// No `woodcase` executable was found in any of the searched directories.
        case binaryNotFound([URL])

        /// The named fixture is not in `Tests/WoodcaseTests/Fixtures`.
        case fixtureNotFound(String)

        /// A sentence naming what was looked for and where.
        var description: String {
            switch self {
            case let .binaryNotFound(searched):
                """
                Could not find the built `woodcase` binary in \
                \(searched.map(\.path).joined(separator: ", ")). \
                Run `swift build` first, or set WOODCASE_BINARY to its path.
                """
            case let .fixtureNotFound(name):
                "No fixture named \(name) in Tests/WoodcaseTests/Fixtures."
            }
        }
    }

    // MARK: - Locating things

    /// The built `woodcase` binary.
    ///
    /// `$WOODCASE_BINARY` wins if it is set. Otherwise the products directory is found
    /// the way an XCTest bundle finds it — the directory the test bundle sits in —
    /// falling back to the package's own `.build` directories, located from this file.
    ///
    /// - Returns: The executable's URL.
    /// - Throws: ``LaunchFailure/binaryNotFound(_:)`` when none of them holds one.
    static func binary() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["WOODCASE_BINARY"],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        var searched: [URL] = []
        for directory in productsDirectories() {
            searched.append(directory)
            let candidate = directory.appendingPathComponent("woodcase")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw LaunchFailure.binaryNotFound(searched)
    }

    /// Every directory the binary might have been built into, best guess first.
    private static func productsDirectories() -> [URL] {
        var directories: [URL] = []
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            directories.append(bundle.bundleURL.deletingLastPathComponent())
        }
        directories.append(Bundle.main.bundleURL)
        let build = packageRoot.appendingPathComponent(".build", isDirectory: true)
        for configuration in ["debug", "release"] {
            directories.append(build.appendingPathComponent(configuration, isDirectory: true))
        }
        return directories
    }

    /// The package root, three directories above this file.
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The fixtures the library's own tests use, which this target borrows.
    private static let fixtures = packageRoot
        .appendingPathComponent("Tests/WoodcaseTests/Fixtures", isDirectory: true)

    private static func copy(fixture: String, into directory: URL) throws -> URL {
        let source = fixtures.appendingPathComponent(fixture)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw LaunchFailure.fixtureNotFound(fixture)
        }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// The environment a run gets: this process's, redirected into ``root``.
    private func environment(adding overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[ActivityLog.homeEnvironmentVariable] = home.path
        environment["HOME"] = root.path
        environment.removeValue(forKey: Identity.environmentVariable)
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }
}
