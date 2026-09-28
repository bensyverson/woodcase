//
//  PenImportProblem.swift
//  Woodcase
//

import Foundation

/// Why one of a document's `imports` contributes nothing.
///
/// A problem is never a failure: the document still reads, and every instance of a
/// component the library would have supplied draws as nothing — which is what Pen does
/// with the same file. ``DocumentLinter`` turns each one into a finding at the top of
/// its report. See <doc:PenImportNamespaces>.
public enum PenImportProblem: Friendly {
    /// No file at the location the import names, resolved against the importing
    /// document's own directory. `url` is the one place that was looked: Pen tries no
    /// other.
    case notFound(alias: String, path: String, url: URL)

    /// The file is there, but it is not a .pen document this build can read.
    case unreadable(alias: String, path: String, reason: String)

    /// An import in ``PenLibraries/bundledScheme``: a library bundled with Pen itself, which Pen reads from its
    /// own install and never from the document's folder. Woodcase does not ship Pen's
    /// libraries, so it has nothing to read.
    case bundled(alias: String, path: String)

    /// A location that is not a file — `https:`, say. A read never goes to the network.
    case remote(alias: String, path: String)

    /// The library itself imports another, which Pen does not follow: a component of
    /// the library that reaches through `nestedAlias` draws nothing in either tool.
    case notFollowed(alias: String, path: String, nestedAlias: String, nestedPath: String)

    /// The import alias the problem belongs to — the host document's, never a nested one.
    public var alias: String {
        switch self {
        case let .notFound(alias, _, _), let .unreadable(alias, _, _), let .bundled(alias, _),
             let .remote(alias, _), let .notFollowed(alias, _, _, _):
            alias
        }
    }

    /// The import path as the document writes it.
    public var path: String {
        switch self {
        case let .notFound(_, path, _), let .unreadable(_, path, _), let .bundled(_, path),
             let .remote(_, path), let .notFollowed(_, path, _, _):
            path
        }
    }

    /// One sentence saying what happened and what it costs, for a lint finding.
    public var message: String {
        switch self {
        case let .notFound(alias, path, url):
            "imports `\(alias)` from `\(path)`, but there is no file at \(url.path); "
                + "every `\(alias):` instance renders as nothing. A bare name is the file "
                + "beside this document — Pen looks nowhere else."
        case let .unreadable(alias, path, reason):
            "imports `\(alias)` from `\(path)`, which is not a readable .pen document "
                + "(\(reason)); every `\(alias):` instance renders as nothing."
        case let .bundled(alias, path):
            "imports `\(alias)` from `\(path)`, a library bundled with Pen, which Woodcase "
                + "does not have; every `\(alias):` instance renders as nothing here. Copy the "
                + "library beside this document and import it by file name to read it."
        case let .remote(alias, path):
            "imports `\(alias)` from `\(path)`, which is not a file; Woodcase never fetches "
                + "a library, so every `\(alias):` instance renders as nothing."
        case let .notFollowed(alias, path, nestedAlias, nestedPath):
            "imports `\(alias)` from `\(path)`, which itself imports `\(nestedAlias)` from "
                + "`\(nestedPath)`. Pen does not follow a library's own imports, so anything in "
                + "`\(path)` that reaches through `\(nestedAlias):` renders as nothing."
        }
    }
}
