//
//  PenLibraries.swift
//  Woodcase
//

import Foundation

/// The libraries a document's `imports` name, read once, when the document is read.
///
/// This is *read context*: it travels with an ``EditableDocument`` (see
/// ``PenReadContext``) and is never written back. The document's own `imports` table is
/// what persists; these are the files it pointed at, as they stood when it was opened.
///
/// A library is keyed by its import path exactly as the document writes it —
/// `"kit.lib.pen"`, `"../shared/icons.pen"` — which is the key
/// ``PenImportResolver`` looks it up by. Two aliases naming one path share one entry.
///
/// Loading follows Pen, established with its own CLI and recorded in
/// `project/2026-09-26-pen-import-resolution.md`:
///
/// - A path is relative to the importing document's directory, and nowhere else is
///   tried — not the working directory, not a libraries folder.
/// - An absolute path or a `file:` URL is read as it stands.
/// - ``bundledScheme``, then `:<name>`, is a library bundled with Pen, read from Pen's install. Woodcase
///   does not ship those, so it is a ``PenImportProblem/bundled(alias:path:)``.
/// - A library's own `imports` are **not** followed — one level, so there is no cycle
///   to break. A document may import itself, and then it is its own library.
///
/// Nothing here throws: a library that cannot be read is a ``PenImportProblem``, and
/// the document reads regardless.
public struct PenLibraries: Friendly {
    /// The libraries that were read, keyed by import path as written.
    public var documents: [String: PenDocument]

    /// Why each import that contributed nothing contributed nothing, in alias order.
    public var problems: [PenImportProblem]

    /// Creates a set of loaded libraries.
    ///
    /// - Parameters:
    ///   - documents: The libraries, keyed by import path as written.
    ///   - problems: What went wrong with the rest.
    public init(documents: [String: PenDocument] = [:], problems: [PenImportProblem] = []) {
        self.documents = documents
        self.problems = problems
    }

    /// No libraries and no problems: what a document built in memory carries.
    public static let none = PenLibraries()

    /// Adds one ``PenDiagnostic/Severity/warning`` per problem to a collector, for a
    /// verb that draws rather than lints — `shot`, `render` — so a missing library is
    /// said once on standard error, and `render --strict` fails on it. `lint` reports
    /// the same problems as its own findings and never calls this.
    ///
    /// - Parameter diagnostics: The collector to add to.
    public func report(into diagnostics: PenDiagnosticCollector) {
        for problem in problems {
            diagnostics.warn("This document \(problem.message)", stage: .importResolution)
        }
    }
}
