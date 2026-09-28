//
//  ActivityLogLocation.swift
//  Woodcase
//

import Foundation

/// Decides which ``ActivityLog`` a given .pen file writes to.
///
/// State stays with the project it describes, the way a tracker's database does: the log
/// for `~/Work/banking/designs/home.pen` is `~/Work/banking/.woodcase/activity.jsonl`,
/// beside the `.git` that says where the project starts. Everything that reads or writes
/// the log — every verb, the viewer — resolves it here, so there is one rule rather than
/// one rule per call site.
///
/// ## The rule
///
/// 1. `$WOODCASE_HOME`, if set and not empty, is the whole answer: one log at
///    `$WOODCASE_HOME/activity.jsonl`, whatever file is being edited. It is the escape
///    hatch for a test, a sandbox, or a person who wants one feed for everything.
/// 2. Otherwise, walk up from the file's directory to the nearest one holding a `.git`
///    — a directory in a checkout, a file in a worktree — and use `<root>/.woodcase`.
/// 3. Otherwise there is no project, so the log sits beside the file itself, in
///    `<the file's directory>/.woodcase`.
///
/// ```swift
/// let log = ActivityLogLocation.log(for: url)
/// try await log.append(recorder.events)
/// ```
///
/// No log is ever read from or written to a home-wide `~/.woodcase`: one that spans every
/// project on a machine answers "what happened here?" with everything that happened
/// anywhere. That directory — ``WoodcaseHome`` — still exists, and holds the font and
/// image caches, which belong to the user rather than to any project.
public enum ActivityLogLocation {
    /// The log a .pen file's edits are recorded in.
    ///
    /// - Parameters:
    ///   - file: The .pen file being edited. It need not exist yet.
    ///   - environment: The environment to read `$WOODCASE_HOME` from. Defaults to this
    ///     process's.
    /// - Returns: The log, with the ``ActivityLog/Origin`` that explains the choice.
    public static func log(
        for file: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ActivityLog {
        log(inDirectory: file.deletingLastPathComponent(), environment: environment)
    }

    /// The log a directory's work is recorded in — what `activity` and `serve` read when
    /// no file was named, resolved from the working directory.
    ///
    /// - Parameters:
    ///   - directory: The directory to resolve from. It need not exist.
    ///   - environment: The environment to read `$WOODCASE_HOME` from. Defaults to this
    ///     process's.
    /// - Returns: The log, with the ``ActivityLog/Origin`` that explains the choice.
    public static func log(
        inDirectory directory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ActivityLog {
        if let override = WoodcaseHome.override(in: environment) {
            return ActivityLog(home: override, origin: .environmentOverride)
        }
        let base = directory.standardizedFileURL
        if let root = repositoryRoot(above: base) {
            return ActivityLog(home: directoryURL(in: root), origin: .repository(root: root))
        }
        return ActivityLog(home: directoryURL(in: base), origin: .directory)
    }

    /// The distinct logs a set of files depends on, in the order the files were named.
    ///
    /// `woodcase serve a.pen b.pen` follows one log per project, and two files in one
    /// project share a log — so the result is deduplicated by log file. Naming no files
    /// at all is the dashboard case: the working directory's log, alone.
    ///
    /// - Parameters:
    ///   - files: The .pen files being served or read.
    ///   - workingDirectory: What to resolve from when `files` is empty. Defaults to the
    ///     process's current directory.
    ///   - environment: The environment to read `$WOODCASE_HOME` from. Defaults to this
    ///     process's.
    /// - Returns: The logs, deduplicated, first appearance first.
    public static func logs(
        for files: [URL],
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [ActivityLog] {
        guard !files.isEmpty else {
            return [log(inDirectory: workingDirectory, environment: environment)]
        }
        var seen: Set<String> = []
        var resolved: [ActivityLog] = []
        for file in files {
            let candidate = log(for: file, environment: environment)
            guard seen.insert(candidate.fileURL.standardizedFileURL.path).inserted else { continue }
            resolved.append(candidate)
        }
        return resolved
    }

    /// The nearest directory at or above `directory` that holds a `.git`.
    ///
    /// A checkout keeps a `.git` directory and a worktree keeps a `.git` *file*, so the
    /// test is existence, not kind — a worktree is a project like any other and its
    /// agents want their log with them.
    ///
    /// - Parameter directory: Where to start. It need not exist; a path that does not
    ///   resolve simply finds nothing.
    /// - Returns: The repository root, or `nil` if the walk reaches the filesystem root
    ///   without finding one.
    public static func repositoryRoot(above directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let marker = current.appendingPathComponent(gitMarker)
            if FileManager.default.fileExists(atPath: marker.path) {
                // Always a directory URL: `URL` equality is spelling-sensitive, so a root
                // returned with a trailing slash and one returned without would not compare
                // equal even though they are one directory.
                return URL(fileURLWithPath: current.path, isDirectory: true)
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return nil }
            current = parent
        }
    }

    // MARK: - Private

    /// The name that marks a repository root, whether it is a directory or a file.
    private static let gitMarker = ".git"

    /// The `.woodcase` directory inside a root.
    private static func directoryURL(in root: URL) -> URL {
        root.appendingPathComponent(ActivityLog.directoryName, isDirectory: true)
    }
}
