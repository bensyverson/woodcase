//
//  PenFileTransactionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Exercises ``PenFileTransaction``: locking, atomic writes, and the no-op guarantee.
///
/// `layout-vertical.pen` is the working fixture. It was written through
/// ``PenParser/encodeForFile(_:)`` by the migrator, so its bytes are already
/// canonical — ``canonicalFixtureIsByteStable`` asserts that, which is what makes
/// the "unchanged document keeps its bytes" test meaningful rather than vacuous.
struct PenFileTransactionTests {
    // MARK: - Helpers

    private static let fixtureName = "layout-vertical.pen"

    /// The id of a rectangle in `layout-vertical.pen`, used as the edit target.
    private static let targetNodeID = "jSUCH"

    /// How long a test that expects to *get* the lock waits for it.
    ///
    /// The product default is five seconds, which is the right answer for a person at
    /// a terminal and the wrong one inside this suite. A transaction holds the lock
    /// across `MainActor.run`, and ``FileLock`` waits by polling with a 10 ms
    /// `Task.sleep` — a sleep this suite has been measured resuming twelve seconds
    /// later. So a waiter given ten seconds gets roughly *one* attempt, and its budget
    /// measures the machine rather than the lock: at ten seconds
    /// ``concurrentTransactionsSerialize`` failed a loaded soak with a genuine
    /// ``PenFileError/lockTimeout(url:timeout:)`` (leaf `YfptE`). Bounded at "not hung"
    /// scale instead, per `project/gotchas.md`. Tests that expect the timeout *itself*
    /// keep their own short budget — that is the behaviour they assert.
    private static let lockBudget: Duration = .seconds(60)

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    /// Copies a fixture into a fresh temporary directory and returns its URL.
    ///
    /// The caller is responsible for nothing: the directory is left in the
    /// system temp area, uniquely named, and removed by ``withCopiedFixture(_:_:)``.
    private func copyFixture(_ name: String, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixtureURL(name), to: destination)
        return destination
    }

    private func withCopiedFixture<T>(
        _ name: String = fixtureName,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionTests-\(UUID().uuidString)")
        let url = try copyFixture(name, into: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(url)
    }

    private func modificationDate(of url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return try #require(values.contentModificationDate)
    }

    private func directoryContents(of url: URL) throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .sorted()
    }

    /// Renames the target node by appending `suffix` to its current name.
    private static func rename(_ document: EditableDocument, suffix: String) throws -> String {
        var node = try #require(document.nodes[targetNodeID])
        let renamed = (node.common.name ?? "") + suffix
        node.common.name = renamed
        try document.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: targetNodeID, common: node.common)))
        return renamed
    }

    // MARK: - Fixture canonicality

    @Test("The working fixture round-trips through encodeForFile byte for byte")
    func canonicalFixtureIsByteStable() throws {
        let url = try fixtureURL(Self.fixtureName)
        let original = try Data(contentsOf: url)
        let reencoded = try PenParser.encodeForFile(PenParser.parse(original))
        #expect(reencoded == original)
    }

    // MARK: - Reading and writing

    @Test("A body that changes nothing leaves the file's bytes and mtime alone")
    func noOpBodyDoesNotWrite() async throws {
        try await withCopiedFixture { url in
            let before = try Data(contentsOf: url)
            let beforeDate = try modificationDate(of: url)
            try await Task.sleep(for: .milliseconds(20))

            let outcome = try await PenFileTransaction.run(at: url) { document in
                document.nodes.count
            }

            #expect(outcome.didWrite == false)
            #expect(outcome.value > 0)
            try #expect(Data(contentsOf: url) == before)
            try #expect(modificationDate(of: url) == beforeDate)
        }
    }

    @Test("An edited document is written back in canonical form")
    func editedDocumentIsWritten() async throws {
        try await withCopiedFixture { url in
            let outcome = try await PenFileTransaction.run(at: url) { document in
                try Self.rename(document, suffix: "-edited")
            }

            #expect(outcome.didWrite)
            #expect(outcome.url == url)
            let reloaded = try PenParser.parse(contentsOf: url)
            let editable = await EditableDocument(from: reloaded)
            let name = await editable.nodes[Self.targetNodeID]?.common.name
            #expect(name == outcome.value)
            // The bytes on disk are the canonical encoding, not merely valid JSON.
            try #expect(Data(contentsOf: url) == PenParser.encodeForFile(reloaded))
        }
    }

    @Test("A successful write leaves no temporary file behind")
    func successfulWriteLeavesNoTempFile() async throws {
        try await withCopiedFixture { url in
            _ = try await PenFileTransaction.run(at: url) { document in
                try Self.rename(document, suffix: "-tidy")
            }
            try #expect(directoryContents(of: url) == [Self.fixtureName])
        }
    }

    @Test("A written file keeps the original's permissions")
    func writePreservesPermissions() async throws {
        try await withCopiedFixture { url in
            #expect(chmod(url.path, 0o640) == 0)

            _ = try await PenFileTransaction.run(at: url) { document in
                try Self.rename(document, suffix: "-chmod")
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.uint16Value == 0o640)
        }
    }

    @Test("A body that throws writes nothing and leaves no temporary file")
    func throwingBodyWritesNothing() async throws {
        try await withCopiedFixture { url in
            let before = try Data(contentsOf: url)
            let beforeDate = try modificationDate(of: url)
            try await Task.sleep(for: .milliseconds(20))

            struct Boom: Error {}
            await #expect(throws: Boom.self) {
                _ = try await PenFileTransaction.run(at: url) { document in
                    _ = try Self.rename(document, suffix: "-doomed")
                    throw Boom()
                }
            }

            try #expect(Data(contentsOf: url) == before)
            try #expect(modificationDate(of: url) == beforeDate)
            try #expect(directoryContents(of: url) == [Self.fixtureName])
        }
    }

    @Test("The read-only variant never writes, even when the body edits")
    func readOnlyVariantDoesNotWrite() async throws {
        try await withCopiedFixture { url in
            let before = try Data(contentsOf: url)
            let beforeDate = try modificationDate(of: url)
            try await Task.sleep(for: .milliseconds(20))

            let outcome = try await PenFileTransaction.read(at: url) { document in
                try Self.rename(document, suffix: "-ignored")
            }

            #expect(outcome.didWrite == false)
            try #expect(Data(contentsOf: url) == before)
            try #expect(modificationDate(of: url) == beforeDate)
        }
    }

    @Test("Concurrent readers do not block each other")
    func concurrentReadsDoNotBlock() async throws {
        try await withCopiedFixture { url in
            async let first = PenFileTransaction.read(at: url, timeout: Self.lockBudget) { $0.nodes.count }
            async let second = PenFileTransaction.read(at: url, timeout: Self.lockBudget) { $0.nodes.count }
            let counts = try await [first.value, second.value]
            #expect(counts[0] == counts[1])
            #expect(counts[0] > 0)
        }
    }

    // MARK: - Errors

    @Test("A nonexistent path throws a typed error naming it")
    func missingFileThrowsTypedError() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionTests-\(UUID().uuidString)")
            .appendingPathComponent("absent.pen")

        await #expect(throws: PenFileError.self) {
            _ = try await PenFileTransaction.run(at: url) { $0.nodes.count }
        }

        do {
            _ = try await PenFileTransaction.run(at: url) { $0.nodes.count }
            Issue.record("expected a PenFileError")
        } catch let error as PenFileError {
            guard case let .cannotOpen(errorURL, _) = error else {
                Issue.record("expected .cannotOpen, got \(error)")
                return
            }
            #expect(errorURL == url)
            #expect(error.description.contains(url.path))
        }
    }

    /// The parser's own error comes through rather than a ``PenFileError`` wrapping it,
    /// so a verb reading under a transaction prints the same sentence — the key path
    /// and all — as one that parsed the file itself.
    @Test("An unparseable file throws the parser's own error, naming it")
    func unparseableFileThrowsTypedError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.pen")
        try Data(#"{"version": "2.17", "children": [{"id": 5}]}"#.utf8).write(to: url)

        do {
            _ = try await PenFileTransaction.run(at: url) { $0.nodes.count }
            Issue.record("expected a PenParserError")
        } catch let error as PenParserError {
            guard case let .decodingFailed(errorURL, _) = error else {
                Issue.record("expected .decodingFailed, got \(error)")
                return
            }
            #expect(errorURL == url)
            #expect(error.description.contains(url.path))
            #expect(error.description.contains("children[0].id should be a string"))
        }
    }

    @Test("A lock held past the timeout fails with a typed error rather than hanging")
    func heldLockTimesOut() async throws {
        try await withCopiedFixture { url in
            let descriptor = open(url.path, O_RDWR)
            #expect(descriptor >= 0)
            #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            defer {
                flock(descriptor, LOCK_UN)
                close(descriptor)
            }

            let started = ContinuousClock.now
            do {
                _ = try await PenFileTransaction.run(at: url, timeout: .milliseconds(200)) { $0.nodes.count }
                Issue.record("expected a lock timeout")
            } catch let error as PenFileError {
                guard case let .lockTimeout(errorURL, timeout) = error else {
                    Issue.record("expected .lockTimeout, got \(error)")
                    return
                }
                #expect(errorURL == url)
                #expect(timeout == .milliseconds(200))
                #expect(error.description.contains(url.path))
            }
            // The typed error is the real proof that nothing hung; this bound only
            // catches an unbounded wait. It is deliberately far above the 200ms
            // timeout: the poll loop's `Task.sleep` resumes late — tens of seconds
            // late, measured — when the whole suite runs its tests in parallel.
            #expect(started.duration(to: .now) < .seconds(120))
        }
    }

    @Test("A writer blocks a reader, which then times out")
    func exclusiveLockBlocksReaders() async throws {
        try await withCopiedFixture { url in
            let descriptor = open(url.path, O_RDWR)
            #expect(descriptor >= 0)
            #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            defer {
                flock(descriptor, LOCK_UN)
                close(descriptor)
            }

            await #expect(throws: PenFileError.self) {
                _ = try await PenFileTransaction.read(at: url, timeout: .milliseconds(200)) { $0.nodes.count }
            }
        }
    }

    // MARK: - Concurrency

    @Test("Two concurrent transactions serialize; neither loses the other's edit")
    func concurrentTransactionsSerialize() async throws {
        try await withCopiedFixture { url in
            async let first = PenFileTransaction.run(at: url, timeout: Self.lockBudget) { document in
                try Self.rename(document, suffix: "-A")
            }
            async let second = PenFileTransaction.run(at: url, timeout: Self.lockBudget) { document in
                try Self.rename(document, suffix: "-B")
            }
            let outcomes = try await [first, second]
            #expect(outcomes[0].didWrite)
            #expect(outcomes[1].didWrite)

            let reloaded = try PenParser.parse(contentsOf: url)
            let editable = await EditableDocument(from: reloaded)
            let name = try await #require(editable.nodes[Self.targetNodeID]?.common.name)
            #expect(name.contains("-A"), "lost the first transaction's edit: \(name)")
            #expect(name.contains("-B"), "lost the second transaction's edit: \(name)")
        }
    }
}
