//
//  WoodcaseHome.swift
//  Woodcase
//

import Foundation

/// The directory Woodcase keeps a user's own state in: `$WOODCASE_HOME`, or `~/.woodcase`.
///
/// Three things ask this question — the activity log's environment override, the Google
/// font cache and the remote image cache — so one enum answers it. A second copy of the
/// rule would drift the first time the default moved.
///
/// ```swift
/// let fonts = WoodcaseHome.directory().appendingPathComponent("fonts")
/// ```
///
/// ## Why not the platform cache directory
///
/// The caches used to live under `{cachesDirectory}/com.bensyverson.woodcase`, which is
/// two things at once: purgeable by the OS under storage pressure, and inside the part
/// of `~/Library` an agent harness walls off with the rest of the home directory. A
/// sandboxed `woodcase tree` therefore measured every downloaded face in the fallback
/// font while its notice blamed a missing download. `~/.woodcase` is the directory the
/// activity log already uses and the one a harness has already been told about.
///
/// ## The override is not a default
///
/// ``override(in:)`` answers `nil` when `$WOODCASE_HOME` is unset *or empty*, so a
/// caller can tell "the user said where" from "nobody said". ``ActivityLogLocation``
/// needs that difference: with no override it looks for the project the file belongs to
/// rather than falling back here, because one home-wide log would answer "what happened
/// here?" with everything that happened anywhere. The caches have no project to belong
/// to, so they take ``directory(in:)`` and its `~/.woodcase` default.
public enum WoodcaseHome {
    /// The environment variable that moves Woodcase's directory.
    public static let environmentVariable = "WOODCASE_HOME"

    /// The directory name Woodcase uses, in a user's home and at a repository root alike.
    public static let directoryName = ".woodcase"

    /// The directory `$WOODCASE_HOME` names, if it names one.
    ///
    /// - Parameter environment: The environment to read. Defaults to this process's.
    /// - Returns: The directory the variable names, or `nil` when it is unset or empty.
    public static func override(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let value = environment[environmentVariable], !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// Woodcase's directory for this user: the override, or `~/.woodcase`.
    ///
    /// Nothing is created here — the first write creates what it needs, the way the
    /// activity log creates its directory on the first append.
    ///
    /// - Parameter environment: The environment to read. Defaults to this process's.
    /// - Returns: The directory. It need not exist.
    public static func directory(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        override(in: environment)
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }
}
