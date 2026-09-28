//
//  ActivityReaderNewestTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises the one question a writer asks the log — "is the file still where the log
/// left it?" — which is answered from the *end* of the file, so that a transaction does
/// not decode the whole history before every write.
struct ActivityReaderNewestTests {
    // MARK: - Helpers

    /// A log in its own temporary directory.
    private func withLog<T>(_ body: (ActivityLog) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityReaderNewestTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await body(ActivityLog(home: directory))
    }

    /// One event for a file, at a revision.
    private static func event(file: URL, revision: String, paths: [String] = []) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: 1),
            identity: "ana",
            file: file,
            op: .set,
            nodes: paths.isEmpty ? [] : ["Ttl01"],
            paths: paths,
            revision: revision,
            batch: "B1"
        )
    }

    private static let first = URL(fileURLWithPath: "/tmp/newest-one.pen")
    private static let second = URL(fileURLWithPath: "/tmp/newest-two.pen")

    // MARK: - Cases

    @Test("A log that does not exist yet has no newest event")
    func missingLogIsEmpty() async throws {
        try await withLog { log in
            let newest = try ActivityReader(log: log).newest(file: Self.first)
            #expect(newest == nil)
        }
    }

    @Test("The newest event is the last line appended")
    func newestIsTheLastLine() async throws {
        try await withLog { log in
            try await log.append([
                Self.event(file: Self.first, revision: "aaaa"),
                Self.event(file: Self.first, revision: "bbbb"),
            ])
            let reader = ActivityReader(log: log)
            #expect(try reader.newest(file: Self.first)?.revision == "bbbb")
            #expect(try reader.newest()?.revision == "bbbb")
        }
    }

    @Test("Another file's newer events are read past, not answered with")
    func filtersByFile() async throws {
        try await withLog { log in
            try await log.append([Self.event(file: Self.first, revision: "aaaa")])
            try await log.append([Self.event(file: Self.second, revision: "bbbb")])
            #expect(try ActivityReader(log: log).newest(file: Self.first)?.revision == "aaaa")
            #expect(try ActivityReader(log: log).newest(file: Self.second)?.revision == "bbbb")
        }
    }

    @Test("A file with nothing recorded reads as nothing, however long the log is")
    func unknownFileIsEmpty() async throws {
        try await withLog { log in
            try await log.append((0 ..< 50).map { Self.event(file: Self.second, revision: "r\($0)") })
            let newest = try ActivityReader(log: log).newest(file: Self.first)
            #expect(newest == nil)
        }
    }

    @Test("The backwards walk crosses its own chunk boundary")
    func readsPastOneChunk() async throws {
        try await withLog { log in
            // Well past the 64 KB the walk reads at a time, with the answer at the far
            // end: the wanted file's only event is the oldest line in the log.
            try await log.append([Self.event(file: Self.first, revision: "aaaa")])
            let padding = String(repeating: "x", count: 512)
            try await log.append((0 ..< 400).map {
                Self.event(file: Self.second, revision: "r\($0)", paths: ["\(padding)/\($0)"])
            })
            #expect(try ActivityReader(log: log).newest(file: Self.first)?.revision == "aaaa")
        }
    }

    @Test("The newest event agrees with the forward read that returns the whole page")
    func agreesWithTheForwardRead() async throws {
        try await withLog { log in
            try await log.append((0 ..< 20).map { Self.event(file: Self.first, revision: "r\($0)") })
            let reader = ActivityReader(log: log)
            let newest = try reader.newest(file: Self.first)
            let page = try reader.read(file: Self.first)
            #expect(newest == page.events.last)
        }
    }
}
