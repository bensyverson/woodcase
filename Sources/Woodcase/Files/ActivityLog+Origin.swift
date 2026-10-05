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

        /// The file is a `.umbra` bundle, which keeps its own log in its own
        /// `.woodcase/`, wherever it sits and whatever `$WOODCASE_HOME` says — so the
        /// history travels with the bundle. Every row in such a log is about the one
        /// document the bundle holds, so a reader takes them all whatever path they
        /// were written under: a renamed bundle keeps its history. See <doc:PenBundles>.
        ///
        /// - Parameters:
        ///   - root: The bundle directory.
        ///   - repository: The repository the bundle sits in, if any — whose
        ///     `.gitignore` learns to ignore `.woodcase/` on the first append.
        case bundle(root: URL, repository: URL?)

        /// The repository root, when there is one: the log's own for a
        /// ``repository(root:)`` log, the enclosing one for a ``bundle(root:repository:)``.
        ///
        /// The URL is always a directory URL — `URL` equality is spelling-sensitive, and
        /// a root that arrived with a trailing slash and one that did not would
        /// otherwise be two different origins for one directory.
        public var repositoryRoot: URL? {
            switch self {
            case let .repository(root): root
            case let .bundle(_, repository): repository
            case .environmentOverride, .directory: nil
            }
        }

        /// Whether every row in the log belongs to one document — a bundle's — so a
        /// reader asking about that document takes every row, whatever path it names.
        public var holdsOneDocument: Bool {
            if case .bundle = self { true } else { false }
        }
    }
}
