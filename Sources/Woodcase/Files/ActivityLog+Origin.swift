//
//  ActivityLog+Origin.swift
//  Woodcase
//

import Foundation

public extension ActivityLog {
    /// Why a log is where it is.
    ///
    /// The location is one decision — ``ActivityLogLocation`` makes it — but three
    /// different things follow from *which* answer it gave, so the answer travels with
    /// the log rather than being re-derived from its path:
    ///
    /// - only a ``repository(root:)`` log adds `.woodcase/` to a `.gitignore`; the
    ///   other two have no repository to tell;
    /// - only an ``environmentOverride`` log is worth naming `$WOODCASE_HOME` in an
    ///   error message, because only there did the variable choose the path;
    /// - the docs and `--help` describe the default, which is the other two.
    enum Origin: Friendly {
        /// `$WOODCASE_HOME` named the directory, and nothing else was consulted.
        case environmentOverride

        /// The nearest directory above the file holding a `.git` — a checkout's
        /// directory or a worktree's file — put the log at that root's `.woodcase`.
        ///
        /// - Parameter root: The repository root the log sits inside.
        case repository(root: URL)

        /// No repository was found, so the log sits beside the file it records.
        case directory

        /// The repository root, when there is one.
        ///
        /// The URL is always a directory URL — `URL` equality is spelling-sensitive, and
        /// a root that arrived with a trailing slash and one that did not would
        /// otherwise be two different origins for one directory.
        public var repositoryRoot: URL? {
            guard case let .repository(root) = self else { return nil }
            return root
        }
    }
}
