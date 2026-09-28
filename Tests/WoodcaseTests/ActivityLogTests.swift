//
//  ActivityLogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises ``ActivityLog``: where it lives, how it appends under a lock, and
/// what rotation does to the live file.
struct ActivityLogTests {
    // MARK: - Helpers

    /// A fresh, empty directory to point `WOODCASE_HOME` at.
    private func withTemporaryHome<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityLogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private static func event(
        identity: String = "logger",
        file: String = "/Users/agent/Designs/demo.pen",
        revision: String
    ) -> ActivityEvent {
        ActivityEvent(
            time: Date(),
            identity: identity,
            file: URL(fileURLWithPath: file),
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            inverse: [.deleteNode(EditOperation.DeleteNode(nodeID: "jSUCH"))],
            revision: revision,
            batch: "b1"
        )
    }

    private func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)
    }

    // MARK: - Location

    @Test("The log file sits inside the directory it was given")
    func fileURLIsInsideTheGivenDirectory() {
        let log = ActivityLog(home: URL(fileURLWithPath: "/var/state/woodcase", isDirectory: true))
        #expect(log.fileURL.path == "/var/state/woodcase/activity.jsonl")
    }

    @Test("A log made from a directory alone is not a repository's to ignore")
    func aBareDirectoryHasNoRepositoryOrigin() {
        #expect(ActivityLog(home: URL(fileURLWithPath: "/var/state/woodcase")).origin == .directory)
    }

    // MARK: - Appending

    @Test("Appending creates the directory and writes one line per event")
    func appendWritesOneLinePerEvent() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1"), Self.event(revision: "r2")])

            let written = try lines(of: log.fileURL)
            #expect(written.count == 2)
            let decoded = try written.map { try ActivityEvent(line: Data($0.utf8)) }
            #expect(decoded.map(\.revision) == ["r1", "r2"])
        }
    }

    @Test("A second append adds to the file rather than replacing it")
    func appendIsAppendOnly() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1")])
            try await log.append([Self.event(revision: "r2")])
            #expect(try lines(of: log.fileURL).count == 2)
        }
    }

    @Test("Appending nothing does not create the file")
    func appendingNothingCreatesNothing() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([])
            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    @Test("A directory that cannot be created fails in one line, naming the log")
    func unmakeableDirectoryIsOneLine() async throws {
        try await withTemporaryHome { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let blocker = directory.appendingPathComponent("blocker")
            try Data("x".utf8).write(to: blocker)
            let log = ActivityLog(home: blocker.appendingPathComponent("home", isDirectory: true))

            await #expect(throws: PenFileError.self) {
                try await log.append([Self.event(revision: "r1")])
            }
            do {
                try await log.append([Self.event(revision: "r1")])
            } catch let error as PenFileError {
                guard case let .writeFailed(url, reason) = error else {
                    Issue.record("expected a write failure, got \(error)")
                    return
                }
                #expect(url == log.fileURL)
                #expect(!reason.contains("\n"))
                #expect(!reason.contains("UserInfo"))
            }
        }
    }

    // MARK: - Rotation

    @Test("A log past the threshold is moved aside and the live file starts fresh")
    func rotationMovesTheOldFileAside() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let filler = Data(repeating: 0x0A, count: Int(ActivityLog.rotationThreshold) + 1)
            try filler.write(to: log.fileURL)

            try await log.append([Self.event(revision: "after")])

            #expect(try lines(of: log.fileURL).count == 1)
            let archives = try FileManager.default
                .contentsOfDirectory(atPath: home.path)
                .filter { $0 != "activity.jsonl" }
                .sorted()
            #expect(archives.count == 1)
            let archive = try #require(archives.first)
            #expect(archive.hasPrefix("activity."))
            #expect(archive.hasSuffix(".jsonl"))
            let archived = try Data(contentsOf: home.appendingPathComponent(archive))
            #expect(archived.count == filler.count)
        }
    }

    @Test("A log under the threshold is not rotated")
    func smallLogIsNotRotated() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1")])
            try await log.append([Self.event(revision: "r2")])
            let entries = try FileManager.default.contentsOfDirectory(atPath: home.path)
            #expect(entries == ["activity.jsonl"])
        }
    }

    // MARK: - Concurrency

    @Test("Concurrent appends never interleave a line")
    func concurrentAppendsProduceWellFormedLines() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let writers = 8
            let perWriter = 5

            await withTaskGroup(of: Void.self) { group in
                for writer in 0 ..< writers {
                    group.addTask {
                        let events = (0 ..< perWriter).map {
                            Self.event(identity: "w\(writer)", revision: "r\(writer)-\($0)")
                        }
                        try? await log.append(events, timeout: .seconds(30))
                    }
                }
            }

            let written = try lines(of: log.fileURL)
            #expect(written.count == writers * perWriter)
            let decoded = try written.map { try ActivityEvent(line: Data($0.utf8)) }
            #expect(Set(decoded.map(\.revision)).count == writers * perWriter)
        }
    }
}
