//
//  ActivityCursorStoreTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ActivityCursorStore``: where an identity's last look at a file is kept.
struct ActivityCursorStoreTests {
    private func withStore<T>(_ body: (ActivityCursorStore, URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityCursorStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = ActivityLog(home: directory.appendingPathComponent("home"))
        return try await body(ActivityCursorStore(log: log), directory)
    }

    @Test("A saved cursor reads back for the same identity and file")
    func savedCursorReadsBack() async throws {
        try await withStore { store, directory in
            let file = directory.appendingPathComponent("design.pen")
            let cursor = ActivityCursor(inode: 0x1A2B, offset: 4096)

            try await store.save(cursor, identity: "claude", file: file)

            #expect(try store.cursor(identity: "claude", file: file) == cursor)
        }
    }

    @Test("Nothing is stored for an identity or a file that never saved")
    func unknownIsNil() async throws {
        try await withStore { store, directory in
            let file = directory.appendingPathComponent("design.pen")
            try await store.save(ActivityCursor(inode: 1, offset: 2), identity: "claude", file: file)

            #expect(try store.cursor(identity: "claude", file: file) != nil)
            #expect(try store.cursor(identity: "codex", file: file) == nil)
            #expect(try store.cursor(identity: "claude", file: directory.appendingPathComponent("other.pen")) == nil)
        }
    }

    @Test("One identity keeps a cursor per file, and a save replaces only its own")
    func cursorPerFile() async throws {
        try await withStore { store, directory in
            let first = directory.appendingPathComponent("a.pen")
            let second = directory.appendingPathComponent("b.pen")
            try await store.save(ActivityCursor(inode: 1, offset: 10), identity: "claude", file: first)
            try await store.save(ActivityCursor(inode: 1, offset: 20), identity: "claude", file: second)
            try await store.save(ActivityCursor(inode: 1, offset: 30), identity: "claude", file: first)

            #expect(try store.cursor(identity: "claude", file: first) == ActivityCursor(inode: 1, offset: 30))
            #expect(try store.cursor(identity: "claude", file: second) == ActivityCursor(inode: 1, offset: 20))
        }
    }

    @Test("Two spellings of one file share a cursor")
    func canonicalFileKey() async throws {
        try await withStore { store, directory in
            let file = directory.appendingPathComponent("design.pen")
            let other = directory.appendingPathComponent("sub/../design.pen")
            try await store.save(ActivityCursor(inode: 3, offset: 4), identity: "claude", file: file)

            #expect(try store.cursor(identity: "claude", file: other) == ActivityCursor(inode: 3, offset: 4))
        }
    }

    @Test("Cursors live in cursors/<identity>.json beside the log, whatever the name holds")
    func fileLocation() async throws {
        try await withStore { store, directory in
            let file = directory.appendingPathComponent("design.pen")
            try await store.save(ActivityCursor(inode: 1, offset: 1), identity: "claude", file: file)
            try await store.save(ActivityCursor(inode: 1, offset: 2), identity: "../Ben S", file: file)

            let cursors = directory.appendingPathComponent("home/cursors")
            let names = try FileManager.default.contentsOfDirectory(atPath: cursors.path).sorted()
            #expect(names.contains("claude.json"))
            #expect(names.count == 2)
            #expect(names.allSatisfy { !$0.contains("/") && !$0.hasPrefix(".") })
            #expect(try store.cursor(identity: "../Ben S", file: file) == ActivityCursor(inode: 1, offset: 2))
        }
    }

    @Test("Saves racing for one identity lose nothing")
    func concurrentSavesKeepEveryFile() async throws {
        try await withStore { store, directory in
            let files = (0 ..< 8).map { directory.appendingPathComponent("f\($0).pen") }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, file) in files.enumerated() {
                    group.addTask {
                        try await store.save(ActivityCursor(inode: 1, offset: UInt64(index)), identity: "claude", file: file)
                    }
                }
                try await group.waitForAll()
            }

            for (index, file) in files.enumerated() {
                #expect(try store.cursor(identity: "claude", file: file) == ActivityCursor(inode: 1, offset: UInt64(index)))
            }
        }
    }
}
