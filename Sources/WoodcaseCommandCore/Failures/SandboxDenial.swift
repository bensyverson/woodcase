//
//  SandboxDenial.swift
//  WoodcaseCommandCore
//

import Foundation

/// Recognises an operation refused by a sandbox, and gives every verb that can hit one
/// — binding a port, writing the activity log, writing the font cache — the same
/// sentence.
///
/// A sandbox says no with the same two POSIX codes an ordinary permissions problem
/// uses — `EPERM` ("Operation not permitted") and `EACCES` ("Permission denied") — so
/// nothing distinguishes "a sandbox forbids this" from "this really is read-only"
/// beyond context: a fresh process denied the very first thing it tries (binding
/// `127.0.0.1`, creating a directory under `~/Library/Caches`) is the sandboxed case
/// in practice. ``matches(_:)`` answers only "was this `EPERM` or `EACCES`"; a caller
/// that knows the context supplies what the sandbox is blocking to ``sentence(forbidding:)``.
enum SandboxDenial {
    /// True when `error` is the OS's way of saying "not allowed here."
    ///
    /// Checks the raw POSIX errno first, when `error` bridges to one (a `POSIXError`,
    /// or a `CocoaError` wrapping one — the shape `Data.write(to:)` and
    /// `FileManager.createDirectory` throw). Some failures in this codebase carry only
    /// a rendered string, not the errno itself — ``Woodcase/PenFileError``'s `reason`
    /// comes from `strerror`, and `Network`'s listener failure is reported as a
    /// description built the same way — so this falls back to the exact text either
    /// produces.
    ///
    /// - Parameter error: The failure to inspect.
    /// - Returns: `true` for `EPERM` or `EACCES`, under any of those representations.
    static func matches(_ error: any Error) -> Bool {
        if let code = posixCode(error) {
            return code == EPERM || code == EACCES
        }
        let text = String(describing: error)
        return text.contains("Operation not permitted") || text.contains("Permission denied")
    }

    /// One sentence naming the restriction and the remedy.
    ///
    /// - Parameter action: What the sandbox is blocking, worded to follow "forbids" —
    ///   "listening on a port", "writing the activity log /path/to/it".
    /// - Returns: A complete sentence, capitalized, ending with the remedy.
    static func sentence(forbidding action: String) -> String {
        "The environment forbids \(action) (a sandbox); rerun with the sandbox disabled."
    }

    /// The raw POSIX errno inside `error`, when it carries one.
    ///
    /// Every Swift `Error` bridges to `NSError`; this checks its domain directly and,
    /// for a `CocoaError` wrapping a lower-level failure, the domain of the error
    /// under `NSUnderlyingErrorKey`.
    ///
    /// - Parameter error: The failure to inspect.
    /// - Returns: The errno, or `nil` if neither `error` nor its underlying error is a
    ///   POSIX error.
    private static func posixCode(_ error: any Error) -> Int32? {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return Int32(nsError.code)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain
        {
            return Int32(underlying.code)
        }
        return nil
    }
}
