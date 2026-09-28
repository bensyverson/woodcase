//
//  PenReadContext.swift
//  Woodcase
//

import Foundation

/// What a document was read *with*: the facts about where it came from that the file
/// itself does not hold, and that every read of it must share.
///
/// An ``EditableDocument`` carries one as ``EditableDocument/readContext``, and nothing
/// in it is ever written back — ``EditableDocument/materialize()`` never looks at it.
/// ``PenFileTransaction`` fills it in once, as it parses the file; a document built in
/// memory carries ``none``.
///
/// Two things ride here, because both are needed wherever a document settles and
/// neither belongs in the file:
///
/// - **The libraries** its `imports` name (``PenLibraries``), so `tree`, `lint`, `shot`,
///   `render`, `generate`, the viewer and a script all expand the same imported
///   instances. See <doc:PenImportNamespaces>.
/// - **The font resolver** its text is measured through. `nil` — the in-memory default —
///   measures in the faces this process already has and consults no cache, so a test
///   that builds a document by hand cannot measure differently on a machine with
///   Google fonts cached in `$WOODCASE_HOME`. A command-line read names
///   ``GoogleFontResolver/shared``; a test names a resolver over a temporary cache.
///
/// Not `Friendly`, on purpose: a ``GoogleFontResolver`` is a live object with a cache
/// and a fetcher, not a value to encode or compare.
public struct PenReadContext: Sendable {
    /// The file the document was read from, when there was one: the base a relative
    /// import path — and a relative url in the document's `fonts` — resolves against.
    public var sourceURL: URL?

    /// The libraries the document's `imports` named when it was read.
    public var libraries: PenLibraries

    /// The resolver whose on-disk cache a settled read registers fonts from, or `nil`
    /// to measure in the faces the process already has.
    public var fonts: GoogleFontResolver?

    /// Creates a read context.
    ///
    /// - Parameters:
    ///   - sourceURL: The file the document came from, if any.
    ///   - libraries: The libraries its `imports` name.
    ///   - fonts: The font resolver a settled read registers fonts through, or `nil`.
    public init(sourceURL: URL? = nil, libraries: PenLibraries = .none, fonts: GoogleFontResolver? = nil) {
        self.sourceURL = sourceURL
        self.libraries = libraries
        self.fonts = fonts
    }

    /// No file, no libraries, no font cache: what a document built in memory carries.
    public static let none = PenReadContext()
}
