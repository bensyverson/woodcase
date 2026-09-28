//
//  TestOutputDirectory.swift
//  WoodcaseTests
//

import Foundation

/// A per-process scratch directory for test-rendered PNGs and debug HTML.
///
/// Several suites render fixtures to disk for visual inspection. A shared fixed
/// path (`/tmp/pen-exports`) let two `swift test` processes running at once — an
/// agent's worktree and `main`, say — overwrite each other's files mid-write, so an
/// MAE comparison could read a half-written PNG. Each process instead gets its own
/// directory under the system temporary directory, named by process id so
/// concurrent runs never collide, created on first use and reused for every call
/// within that process. There is no stable, human-facing copy: nobody reads these
/// files routinely, so the per-process directory is the only output.
///
/// Swift Testing has no hook that runs when the whole run ends, so a run cannot
/// clean up after itself. Instead, the first use sweeps away the folders of
/// processes that have exited. That keeps the last run's output until the next run
/// starts, and never touches the folder of a run still going. Set
/// ``keepVariable`` to keep every folder for debugging.
enum TestOutputDirectory {
    /// The environment variable that, when set, turns off the sweep of old folders.
    static let keepVariable = "WOODCASE_KEEP_TEST_OUTPUT"

    /// The folder-name prefix; the process id follows it.
    private static let prefix = "pen-exports-"

    /// This process's directory for test output.
    static let url: URL = prepare(
        in: FileManager.default.temporaryDirectory,
        processIdentifier: ProcessInfo.processInfo.processIdentifier,
        environment: ProcessInfo.processInfo.environment,
        isAlive: isProcessAlive
    )

    /// The `webview-regression` subfolder under ``url``, carried over from the
    /// fixed path this replaced.
    static let webViewRegressionURL: URL = {
        let dir = url.appendingPathComponent("webview-regression")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Creates the output folder for `processIdentifier` under `parent`, first
    /// removing every `pen-exports-<pid>` folder whose process `isAlive` says has
    /// exited, unless `environment` sets ``keepVariable``.
    static func prepare(
        in parent: URL,
        processIdentifier: Int32,
        environment: [String: String],
        isAlive: (Int32) -> Bool
    ) -> URL {
        if environment[keepVariable] == nil {
            sweep(parent, sparing: processIdentifier, isAlive: isAlive)
        }
        let dir = parent.appendingPathComponent("\(prefix)\(processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Whether a process with this id is running.
    static func isProcessAlive(_ pid: Int32) -> Bool {
        // EPERM means the process exists but belongs to someone else.
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func sweep(_ parent: URL, sparing current: Int32, isAlive: (Int32) -> Bool) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            guard let pid = Int32(name.dropFirst(prefix.count)), pid != current, !isAlive(pid)
            else { continue }
            // Another run may be sweeping the same folder; losing that race is fine.
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
}
