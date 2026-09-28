//
//  ActivityLogLocationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises ``ActivityLogLocation``: which `.woodcase/activity.jsonl` a given .pen file
/// writes to, and the `.gitignore` line the first write leaves behind.
struct ActivityLogLocationTests {
    // MARK: - Helpers

    /// A fresh temporary directory, removed when `body` returns.
    private func withScratch<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityLogLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory.resolvingSymlinksInPath())
    }

    /// Marks a directory as a repository root the way a checkout does — a `.git` directory.
    private func makeCheckout(at root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Marks a directory as a repository root the way a *worktree* does — a `.git` file.
    private func makeWorktree(at root: URL) throws {
        try "gitdir: /elsewhere/.git/worktrees/x\n"
            .write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    }

    /// Makes `directory` and returns it.
    @discardableResult
    private func makeDirectory(_ directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func event(file: URL) -> ActivityEvent {
        ActivityEvent(
            time: Date(),
            identity: "logger",
            file: file,
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            inverse: [],
            revision: "r1",
            batch: "b1"
        )
    }

    // MARK: - Resolution

    @Test("A file inside a checkout logs to the repository root's .woodcase")
    func fileInCheckoutLogsAtTheRoot() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let nested = try makeDirectory(scratch.appendingPathComponent("designs/mobile"))
            let file = nested.appendingPathComponent("demo.pen")

            let log = ActivityLogLocation.log(for: file, environment: [:])
            #expect(log.fileURL.path == scratch.path + "/.woodcase/activity.jsonl")
            #expect(log.origin.repositoryRoot?.path == scratch.path)
        }
    }

    @Test("A worktree's .git file marks a repository root just as a .git directory does")
    func worktreeGitFileIsARoot() async throws {
        try await withScratch { scratch in
            try makeWorktree(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")

            let log = ActivityLogLocation.log(for: file, environment: [:])
            #expect(log.origin.repositoryRoot?.path == scratch.path)
        }
    }

    @Test("The nearest .git above the file wins, not the outermost")
    func nearestRootWins() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let inner = try makeDirectory(scratch.appendingPathComponent("vendor/inner"))
            try makeCheckout(at: inner)
            let file = inner.appendingPathComponent("demo.pen")

            #expect(ActivityLogLocation.log(for: file, environment: [:]).origin.repositoryRoot?.path == inner.path)
        }
    }

    @Test("A file outside any repository logs beside itself")
    func fileOutsideARepositoryLogsBesideItself() async throws {
        try await withScratch { scratch in
            let nested = try makeDirectory(scratch.appendingPathComponent("designs"))
            let file = nested.appendingPathComponent("demo.pen")

            let log = ActivityLogLocation.log(for: file, environment: [:])
            #expect(log.fileURL.path == nested.path + "/.woodcase/activity.jsonl")
            #expect(log.origin == .directory)
        }
    }

    @Test("$WOODCASE_HOME overrides even a file that sits in a repository")
    func environmentOverridesEverything() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")

            let log = ActivityLogLocation.log(
                for: file, environment: [ActivityLog.homeEnvironmentVariable: "/var/state/woodcase"]
            )
            #expect(log.fileURL.path == "/var/state/woodcase/activity.jsonl")
            #expect(log.origin == .environmentOverride)
        }
    }

    @Test("An empty $WOODCASE_HOME is ignored rather than making the log relative")
    func emptyEnvironmentIsIgnored() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")

            let log = ActivityLogLocation.log(
                for: file, environment: [ActivityLog.homeEnvironmentVariable: ""]
            )
            #expect(log.origin.repositoryRoot?.path == scratch.path)
        }
    }

    @Test("A directory resolves the same way a file in it does")
    func directoryResolvesLikeAFileInIt() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let nested = try makeDirectory(scratch.appendingPathComponent("designs"))

            #expect(ActivityLogLocation.log(inDirectory: nested, environment: [:]).fileURL.path
                == ActivityLogLocation.log(for: nested.appendingPathComponent("a.pen"), environment: [:]).fileURL.path)
        }
    }

    // MARK: - Several files at once

    @Test("Two files in one repository share one log")
    func filesInOneRepositoryShareALog() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let first = scratch.appendingPathComponent("a.pen")
            let second = try makeDirectory(scratch.appendingPathComponent("deep"))
                .appendingPathComponent("b.pen")

            let logs = ActivityLogLocation.logs(
                for: [first, second], workingDirectory: scratch, environment: [:]
            )
            #expect(logs.count == 1)
        }
    }

    @Test("Files in two repositories resolve to two logs, in the order the files were named")
    func filesInTwoRepositoriesResolveToTwoLogs() async throws {
        try await withScratch { scratch in
            let left = try makeDirectory(scratch.appendingPathComponent("left"))
            let right = try makeDirectory(scratch.appendingPathComponent("right"))
            try makeCheckout(at: left)
            try makeCheckout(at: right)

            let logs = ActivityLogLocation.logs(
                for: [left.appendingPathComponent("a.pen"), right.appendingPathComponent("b.pen")],
                workingDirectory: scratch,
                environment: [:]
            )
            #expect(logs.map(\.home.path) == [
                left.path + "/.woodcase",
                right.path + "/.woodcase",
            ])
        }
    }

    @Test("No files at all is the working directory's log")
    func noFilesIsTheWorkingDirectorysLog() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let inner = try makeDirectory(scratch.appendingPathComponent("designs"))

            let logs = ActivityLogLocation.logs(for: [], workingDirectory: inner, environment: [:])
            #expect(logs.map(\.home.path) == [scratch.path + "/.woodcase"])
        }
    }

    @Test("With $WOODCASE_HOME set, every file collapses to the one overridden log")
    func overrideCollapsesToOneLog() async throws {
        try await withScratch { scratch in
            let left = try makeDirectory(scratch.appendingPathComponent("left"))
            let right = try makeDirectory(scratch.appendingPathComponent("right"))
            try makeCheckout(at: left)
            try makeCheckout(at: right)

            let logs = ActivityLogLocation.logs(
                for: [left.appendingPathComponent("a.pen"), right.appendingPathComponent("b.pen")],
                workingDirectory: scratch,
                environment: [ActivityLog.homeEnvironmentVariable: scratch.path]
            )
            #expect(logs.count == 1)
        }
    }

    // MARK: - Ignoring the directory

    @Test("The write that creates .woodcase inside a repository ignores it")
    func firstWriteAddsTheIgnoreLine() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")
            let log = ActivityLogLocation.log(for: file, environment: [:])

            try await log.append([Self.event(file: file)])

            let ignore = try String(
                contentsOf: scratch.appendingPathComponent(".gitignore"), encoding: .utf8
            )
            #expect(ignore.contains(ActivityLog.ignorePattern))
        }
    }

    @Test("A second write does not add the ignore line twice")
    func secondWriteDoesNotDuplicateTheIgnoreLine() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")
            let log = ActivityLogLocation.log(for: file, environment: [:])

            try await log.append([Self.event(file: file)])
            try await log.append([Self.event(file: file)])

            let ignore = try String(
                contentsOf: scratch.appendingPathComponent(".gitignore"), encoding: .utf8
            )
            let matches = ignore.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == ActivityLog.ignorePattern }
            #expect(matches.count == 1)
        }
    }

    @Test("An existing .gitignore keeps its contents and gains the line")
    func existingIgnoreFileIsAppendedTo() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let ignoreURL = scratch.appendingPathComponent(".gitignore")
            try ".build\n".write(to: ignoreURL, atomically: true, encoding: .utf8)
            let file = scratch.appendingPathComponent("demo.pen")

            try await ActivityLogLocation.log(for: file, environment: [:]).append([Self.event(file: file)])

            let ignore = try String(contentsOf: ignoreURL, encoding: .utf8)
            #expect(ignore.contains(".build"))
            #expect(ignore.contains(ActivityLog.ignorePattern))
        }
    }

    @Test("A .gitignore that already ignores the directory is left alone")
    func alreadyIgnoredIsLeftAlone() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let ignoreURL = scratch.appendingPathComponent(".gitignore")
            try "/.woodcase\n".write(to: ignoreURL, atomically: true, encoding: .utf8)
            let file = scratch.appendingPathComponent("demo.pen")

            try await ActivityLogLocation.log(for: file, environment: [:]).append([Self.event(file: file)])

            #expect(try String(contentsOf: ignoreURL, encoding: .utf8) == "/.woodcase\n")
        }
    }

    @Test("A file outside any repository leaves no .gitignore behind")
    func outsideARepositoryNothingIsIgnored() async throws {
        try await withScratch { scratch in
            let file = scratch.appendingPathComponent("demo.pen")

            try await ActivityLogLocation.log(for: file, environment: [:]).append([Self.event(file: file)])

            #expect(!FileManager.default.fileExists(
                atPath: scratch.appendingPathComponent(".gitignore").path
            ))
        }
    }

    @Test("A $WOODCASE_HOME inside a repository is not the repository's business to ignore")
    func overriddenHomeIsNotIgnored() async throws {
        try await withScratch { scratch in
            try makeCheckout(at: scratch)
            let file = scratch.appendingPathComponent("demo.pen")
            let home = scratch.appendingPathComponent("elsewhere")

            let log = ActivityLogLocation.log(
                for: file, environment: [ActivityLog.homeEnvironmentVariable: home.path]
            )
            try await log.append([Self.event(file: file)])

            #expect(!FileManager.default.fileExists(
                atPath: scratch.appendingPathComponent(".gitignore").path
            ))
        }
    }
}
