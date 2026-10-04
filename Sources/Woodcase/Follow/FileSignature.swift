//
//  FileSignature.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// What `stat(2)` says about a file, as far as noticing an edit needs.
///
/// An atomic replace changes the inode, an in-place write changes the size or the
/// modification time, and a delete leaves no signature at all — so comparing two
/// signatures catches every way a .pen file changes.
struct FileSignature: Friendly {
    /// The inode number. A rename over the path installs a different one.
    var inode: UInt64
    /// The size in bytes.
    var size: Int64
    /// The modification time in nanoseconds since the epoch.
    var modifiedNanoseconds: Int64

    /// Reads a path's signature.
    ///
    /// - Parameter path: The file to inspect.
    /// - Returns: Its signature, or `nil` when nothing exists at the path.
    static func read(at path: String) -> FileSignature? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileSignature(info)
    }

    /// Reads the signature of an open descriptor.
    ///
    /// - Parameter descriptor: A descriptor from `open(2)`.
    /// - Returns: Its signature, or `nil` if `fstat(2)` fails.
    static func read(descriptor: Int32) -> FileSignature? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return FileSignature(info)
    }

    private init(_ info: stat) {
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        #if canImport(Darwin)
            let time = info.st_mtimespec
        #else
            let time = info.st_mtim
        #endif
        modifiedNanoseconds = Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }
}
