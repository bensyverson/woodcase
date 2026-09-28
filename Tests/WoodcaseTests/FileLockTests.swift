//
//  FileLockTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Exercises ``FileLock`` directly: the mode matrix, the bounded wait, and the
/// descriptor-identity check that keeps a waiter from winning a lock on a file
/// that has since been renamed away.
struct FileLockTests {
    // MARK: - Helpers

    private func withTemporaryFile<T>(
        contents: String = "{}\n",
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("subject.pen")
        try Data(contents.utf8).write(to: url)
        return try await body(url)
    }

    // MARK: - Acquiring

    @Test("An exclusive lock reads the file through its own descriptor")
    func exclusiveLockReadsContents() async throws {
        try await withTemporaryFile(contents: "hello lock") { url in
            let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: .seconds(1))
            defer { lock.release() }
            try #expect(lock.contents() == Data("hello lock".utf8))
            #expect(lock.url == url)
        }
    }

    @Test("Two shared locks are held at the same time")
    func sharedLocksCoexist() async throws {
        try await withTemporaryFile { url in
            let first = try await FileLock.acquire(url, mode: .shared, timeout: .milliseconds(200))
            defer { first.release() }
            let second = try await FileLock.acquire(url, mode: .shared, timeout: .milliseconds(200))
            defer { second.release() }
            #expect(first.descriptor != second.descriptor)
        }
    }

    @Test("An exclusive lock excludes a second exclusive lock until the timeout")
    func exclusiveLockExcludes() async throws {
        try await withTemporaryFile { url in
            let held = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            defer { held.release() }

            await #expect(throws: PenFileError.lockTimeout(url: url, timeout: .milliseconds(150))) {
                _ = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(150))
            }
        }
    }

    @Test("A released lock lets the next waiter through")
    func releasedLockIsReacquirable() async throws {
        try await withTemporaryFile { url in
            let first = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            first.release()
            let second = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            second.release()
        }
    }

    @Test("A missing file cannot be locked")
    func missingFileCannotBeLocked() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLockTests-\(UUID().uuidString)")
            .appendingPathComponent("absent.pen")
        do {
            _ = try await FileLock.acquire(url, mode: .shared, timeout: .milliseconds(50))
            Issue.record("expected a PenFileError")
        } catch let error as PenFileError {
            guard case let .cannotOpen(errorURL, _) = error else {
                Issue.record("expected .cannotOpen, got \(error)")
                return
            }
            #expect(errorURL == url)
        }
    }

    @Test("Locking never creates the file it was asked for")
    func lockingDoesNotCreateTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("absent.pen")

        _ = try? await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(50))
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    // MARK: - Descriptor identity

    @Test("A descriptor describes the file it was opened from")
    func descriptorDescribesItsOwnFile() async throws {
        try await withTemporaryFile { url in
            let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            defer { lock.release() }
            #expect(FileLock.describesFile(descriptor: lock.descriptor, atPath: url.path))
        }
    }

    @Test("A descriptor stops describing its path once another file is renamed over it")
    func descriptorStopsDescribingRenamedPath() async throws {
        try await withTemporaryFile { url in
            let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            defer { lock.release() }

            let replacement = url.deletingLastPathComponent().appendingPathComponent("replacement.pen")
            try Data("{}\n".utf8).write(to: replacement)
            #expect(rename(replacement.path, url.path) == 0)

            #expect(FileLock.describesFile(descriptor: lock.descriptor, atPath: url.path) == false)
        }
    }

    @Test("A descriptor stops describing its path once the file is deleted")
    func descriptorStopsDescribingDeletedPath() async throws {
        try await withTemporaryFile { url in
            let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            defer { lock.release() }
            try FileManager.default.removeItem(at: url)
            #expect(FileLock.describesFile(descriptor: lock.descriptor, atPath: url.path) == false)
        }
    }

    // MARK: - Permissions

    @Test("A lock reports the file's permission bits")
    func lockReportsPermissions() async throws {
        try await withTemporaryFile { url in
            #expect(chmod(url.path, 0o640) == 0)
            let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: .milliseconds(200))
            defer { lock.release() }
            #expect(lock.permissions == 0o640)
        }
    }
}
