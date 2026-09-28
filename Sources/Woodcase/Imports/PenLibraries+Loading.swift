//
//  PenLibraries+Loading.swift
//  Woodcase
//

import Foundation

public extension PenLibraries {
    /// The URL scheme Pen reserves for the libraries it bundles with itself, written
    /// `<scheme>:shadcn.lib.pen`.
    static let bundledScheme = "pencil"

    /// Reads every library a document's `imports` name.
    ///
    /// Each distinct path is read once, however many aliases name it. A path that
    /// names the document itself is answered with `document` rather than read again —
    /// the file may be locked by the transaction doing the reading, and in any case the
    /// document in hand is what those bytes parse to.
    ///
    /// - Parameters:
    ///   - document: The document whose `imports` to read.
    ///   - url: Where the document itself lives: the base every relative path is
    ///     resolved against.
    /// - Returns: The libraries that could be read, and a problem for each that could not.
    static func load(importedBy document: PenDocument, at url: URL) -> PenLibraries {
        guard let imports = document.imports, !imports.isEmpty else { return .none }
        let host = url.standardizedFileURL
        var loaded = PenLibraries()
        var outcomes: [String: Outcome] = [:]

        for alias in imports.keys.sorted() {
            guard let path = imports[alias] else { continue }
            let outcome = outcomes[path] ?? read(path, relativeTo: host, host: document)
            outcomes[path] = outcome
            if let problem = outcome.problem(alias: alias, path: path) {
                loaded.problems.append(problem)
                continue
            }
            guard case let .read(library) = outcome else { continue }
            loaded.documents[path] = library
            let nested = library.imports ?? [:]
            for nestedAlias in nested.keys.sorted() {
                loaded.problems.append(.notFollowed(
                    alias: alias, path: path, nestedAlias: nestedAlias, nestedPath: nested[nestedAlias] ?? ""
                ))
            }
        }
        return loaded
    }

    /// Where an import path points, resolved as Pen resolves it.
    ///
    /// - Parameters:
    ///   - path: The import path as the document writes it.
    ///   - document: The importing document's own file URL.
    /// - Returns: The file to read, or `nil` for a location that is not a file on disk —
    ///   a bundled library (``bundledScheme``) or a remote URL.
    static func location(of path: String, relativeTo document: URL) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        if let scheme = URL(string: path)?.scheme, scheme.count > 1 {
            guard scheme == "file", let url = URL(string: path) else { return nil }
            return url.standardizedFileURL
        }
        return document.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    }
}

// MARK: - Reading one library

private extension PenLibraries {
    /// What reading one path came to, before it is charged to an alias: two aliases
    /// naming one missing path are two problems, one per alias.
    enum Outcome: Friendly {
        case read(PenDocument)
        case notFound(URL)
        case unreadable(String)
        case bundled
        case remote

        /// The problem this outcome is for one alias, or `nil` when the library was read.
        func problem(alias: String, path: String) -> PenImportProblem? {
            switch self {
            case .read: nil
            case let .notFound(url): .notFound(alias: alias, path: path, url: url)
            case let .unreadable(reason): .unreadable(alias: alias, path: path, reason: reason)
            case .bundled: .bundled(alias: alias, path: path)
            case .remote: .remote(alias: alias, path: path)
            }
        }
    }

    /// Reads the library at one import path.
    static func read(_ path: String, relativeTo host: URL, host document: PenDocument) -> Outcome {
        guard let url = location(of: path, relativeTo: host) else {
            return URL(string: path)?.scheme == bundledScheme ? .bundled : .remote
        }
        if url == host { return .read(document) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .notFound(url) }
        do {
            return try .read(PenParser.parse(contentsOf: url))
        } catch {
            return .unreadable((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}
