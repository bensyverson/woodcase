//
//  FileLock.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A whole-file advisory lock, held on an open file descriptor.
///
/// The lock is `flock(2)`, taken on the .pen file itself rather than on a sidecar:
/// the file is the truth, and another tool that opens the same path — another
/// editor, a second `woodcase` process — participates in the same lock. It is
/// **advisory**: a writer that does not ask for the lock is not stopped by it.
/// Everything in Woodcase that opens a .pen file for editing goes through
/// ``PenFileTransaction``, so within Woodcase the lock is total.
///
/// ## Waiting without blocking
///
/// Acquisition never calls a blocking `flock`. It polls with `LOCK_NB` and
/// suspends between attempts with `Task.sleep`, so a caller that waits does not
/// occupy a thread and a caller that is cancelled stops waiting. When the timeout
/// expires the attempt fails with ``PenFileError/lockTimeout(url:timeout:)`` — never
/// a hang.
///
/// ## Rename revalidation
///
/// A transaction commits by renaming a temporary file over the original, which
/// replaces the *inode* at that path. A waiter that opened the path first is
/// holding a descriptor for the old inode, and would win a lock on a file that is
/// no longer there. So after each successful `flock`, the descriptor's identity is
/// compared against the path's; if they differ, the descriptor is dropped and the
/// path is opened again. Without this, two concurrent transactions could each read
/// the file, and the second would overwrite the first's edit.
struct FileLock {
    /// Whether the lock excludes other holders.
    enum Mode {
        /// One holder at a time. Taken by a transaction that may write.
        case exclusive
        /// Any number of concurrent holders, but none while a writer holds the file.
        case shared

        /// The `flock(2)` operation for this mode, without `LOCK_NB`.
        var flockOperation: Int32 {
            switch self {
            case .exclusive: LOCK_EX
            case .shared: LOCK_SH
            }
        }

        /// The `open(2)` access mode this lock needs. Neither creates the file:
        /// a .pen file the caller named but that does not exist is an error, not
        /// an invitation to make an empty one.
        var openFlags: Int32 {
            switch self {
            case .exclusive: O_RDWR
            case .shared: O_RDONLY
            }
        }
    }

    /// The file the lock is held on.
    let url: URL

    /// The open file descriptor carrying the lock.
    let descriptor: Int32

    /// How long to wait between `LOCK_NB` attempts.
    static let pollInterval: Duration = .milliseconds(10)

    /// Takes the lock, waiting up to `timeout` for a competing holder to release it.
    ///
    /// - Parameters:
    ///   - url: The file to lock.
    ///   - mode: Exclusive for a transaction that may write, shared for a read.
    ///   - timeout: How long to keep retrying before giving up.
    /// - Returns: The held lock. The caller must call ``release()``.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the file cannot be opened,
    ///   or ``PenFileError/lockTimeout(url:timeout:)`` if it stays locked past `timeout`.
    static func acquire(_ url: URL, mode: Mode, timeout: Duration) async throws -> FileLock {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let path = url.path

        while true {
            let descriptor = open(path, mode.openFlags)
            guard descriptor >= 0 else {
                throw PenFileError.cannotOpen(url: url, reason: systemMessage(errno))
            }

            if flock(descriptor, mode.flockOperation | LOCK_NB) == 0 {
                if describesFile(descriptor: descriptor, atPath: path) {
                    return FileLock(url: url, descriptor: descriptor)
                }
                // The path was replaced while we waited; start over on the new file.
                flock(descriptor, LOCK_UN)
                close(descriptor)
            } else {
                let failure = errno
                close(descriptor)
                guard failure == EWOULDBLOCK else {
                    throw PenFileError.cannotOpen(url: url, reason: systemMessage(failure))
                }
            }

            guard ContinuousClock.now < deadline else {
                throw PenFileError.lockTimeout(url: url, timeout: timeout)
            }
            try? await Task.sleep(for: pollInterval)
            try Task.checkCancellation()
        }
    }

    /// Releases the lock and closes the descriptor. Safe to call exactly once.
    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Reads the whole locked file from the descriptor.
    ///
    /// Reading through the descriptor rather than the path guarantees the bytes
    /// come from the file the lock is held on, even if the path is replaced
    /// underneath by a tool that ignores the lock.
    ///
    /// - Returns: The file's contents.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the read fails.
    func contents() throws -> Data {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw PenFileError.cannotOpen(url: url, reason: Self.systemMessage(errno))
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< count])
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                throw PenFileError.cannotOpen(url: url, reason: Self.systemMessage(errno))
            }
        }
    }

    /// The locked file's POSIX permission bits, so a replacement written beside it
    /// can be given the same ones before it takes the original's place.
    var permissions: mode_t? {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { return nil }
        return status.st_mode & 0o7777
    }

    // MARK: - Identity

    /// Whether the open descriptor still names the file living at `path`.
    ///
    /// `false` means the path was replaced — by this package's own commit, or by
    /// any other tool — since the descriptor was opened, so the descriptor now
    /// refers to a file nobody can reach by name.
    static func describesFile(descriptor: Int32, atPath path: String) -> Bool {
        var openFile = stat()
        var pathFile = stat()
        guard fstat(descriptor, &openFile) == 0, stat(path, &pathFile) == 0 else { return false }
        return openFile.st_dev == pathFile.st_dev && openFile.st_ino == pathFile.st_ino
    }

    /// The system's message for an `errno` value.
    static func systemMessage(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}
