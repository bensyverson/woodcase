//
//  PenFileTransaction+ReadContext.swift
//  Woodcase
//

import Foundation

extension PenFileTransaction {
    /// Flattens the parsed file and gives it its read context: the libraries its
    /// `imports` name, read once, here, and the font resolver the caller named.
    ///
    /// Reading the libraries never fails the transaction — a library that is not there
    /// is a ``PenImportProblem`` on the context, for `lint` to report. They are read
    /// under the file's lock but without locks of their own: a library is only ever
    /// read, never written, by a transaction on the document that imports it.
    ///
    /// A file holding a component loop is read too, the loop recorded on the context
    /// (``EditableDocument/recordComponentLoopsOnRead()``) for the caller to report.
    static func editableDocument(
        from parsed: PenDocument,
        at url: URL,
        fonts: GoogleFontResolver?
    ) -> EditableDocument {
        let editable = EditableDocument(from: parsed)
        editable.readContext = PenReadContext(
            sourceURL: url,
            libraries: PenLibraries.load(importedBy: parsed, at: url),
            fonts: fonts
        )
        editable.recordComponentLoopsOnRead()
        return editable
    }
}
