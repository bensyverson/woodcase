//
//  ScratchDirectory.swift
//  Woodcase
//

import Foundation

/// The directory a process should stage throwaway files in: `$TMPDIR`, or
/// `FileManager`'s own answer when that is unset.
///
/// `FileManager.default.temporaryDirectory` does not read `$TMPDIR` on macOS — it
/// resolves to the per-user `/var/folders/…/T` regardless of the variable's value. The
/// Claude Code Bash sandbox allows writes to `$TMPDIR` (`/tmp/claude-501`) but denies
/// that other directory outright, so code that stages bytes with the bare API fails
/// sandboxed with `NSCocoaErrorDomain 513` while every test, run with the sandbox off,
/// passes. `GoogleFontResolver.registerFont(data:)` hit exactly this
/// (project/2026-09-26-sandbox-font-downloads.md); this is the one place that
/// disagreement gets resolved, so a second caller does not have to relearn it.
///
/// ```swift
/// let scratch = ScratchDirectory.url()
///     .appendingPathComponent("woodcase-font-\(UUID().uuidString)")
/// ```
public enum ScratchDirectory {
    /// The environment variable macOS and Linux use to relocate a process's scratch
    /// directory.
    public static let environmentVariable = "TMPDIR"

    /// This process's scratch directory.
    ///
    /// - Parameter environment: The environment to read. Defaults to this process's.
    /// - Returns: The directory `$TMPDIR` names, when it names a non-empty one, or
    ///   `FileManager.default.temporaryDirectory` otherwise. Nothing is created here.
    public static func url(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        guard let value = environment[environmentVariable], !value.isEmpty else {
            return FileManager.default.temporaryDirectory
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
