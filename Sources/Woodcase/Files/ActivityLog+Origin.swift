//
//  ActivityLog+Origin.swift
//  Woodcase
//

import Foundation

public extension ActivityLog {
    /// Why a log is where it is.
    ///
    /// The location is one decision — ``ActivityLogLocation`` makes it — but several
    /// things follow from *which* answer it gave, so the answer travels with the log
    /// rather than being re-derived from its path:
    ///
    /// - only a ``repository(root:)`` log adds `.woodcase/` to a repository's
    ///   `.gitignore`; a ``bundle(root:)`` history is meant to be committed, and the
    ///   others have no repository to tell;
    /// - only a ``bundle(root:)`` log is a shared history, one file per writer
    ///   (``ActivityLog/Layout/perWriter``);
    /// - only an ``environmentOverride`` log is worth naming `$WOODCASE_HOME` in an
    ///   error message, because only there did the variable choose the path.
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

        /// The file is a `.umbra` bundle, which keeps its own shared history in its
        /// `history/` — one file per writer — wherever it sits and whatever
        /// `$WOODCASE_HOME` says, so the history travels with the bundle. Every row in it
        /// is about the one document the bundle holds, so a reader takes them all: a
        /// renamed bundle keeps its history. See <doc:PenBundles>.
        ///
        /// - Parameter root: The bundle directory.
        case bundle(root: URL)

        /// The repository root whose `.gitignore` the log's first append edits: a
        /// ``repository(root:)`` log's own; `nil` for every other origin, a bundle's
        /// included — its history is committed on purpose.
        ///
        /// The URL is always a directory URL — `URL` equality is spelling-sensitive, and
        /// a root that arrived with a trailing slash and one that did not would
        /// otherwise be two different origins for one directory.
        public var repositoryRoot: URL? {
            switch self {
            case let .repository(root): root
            case .environmentOverride, .directory, .bundle: nil
            }
        }

        /// Whether every row in the log belongs to one document — a bundle's — so a
        /// reader asking about that document takes every row, whatever path it names.
        public var holdsOneDocument: Bool {
            if case .bundle = self { true } else { false }
        }
    }
}
