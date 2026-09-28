//
//  SettledTree+Ledger.swift
//  Woodcase
//

import Foundation

extension SettledTree {
    /// What a settled tree was assembled from, root by root, and what every piece of it
    /// rests on — the record a later settle reads to decide which roots it can keep.
    package struct Ledger {
        /// The document-wide inputs every root was settled under.
        let basis: Basis

        /// The font set the pieces were measured in, as ``TextSizeCache/fontGeneration``
        /// read it after the settle registered its fonts and before it measured anything.
        let fontGeneration: Int

        /// Each present root's piece, keyed by the root's authored id.
        let pieces: [String: Piece]

        /// The roots this settle laid out, in root order; every other root's piece was
        /// kept from the tree it reused.
        package let laidOut: [String]
    }

    /// The inputs of a settle that no root's revision covers: the theme asked for, the
    /// document's own tables, and the document and read context it was made from.
    ///
    /// A change to any of them can move every root — a variable or a theme axis feeds
    /// every resolution, an import or a new library changes what an instance expands to,
    /// a declared font changes what a text measures in — so a basis that differs reuses
    /// nothing.
    struct Basis: Equatable {
        /// ``EditableDocument/_readContextSerial``: the document, and the libraries and
        /// font resolver it was read with.
        let readContextSerial: Int

        /// The theme axes pinned for the read.
        let theme: [String: String]

        /// ``EditableDocument/version``.
        let version: String

        /// ``EditableDocument/themes``.
        let themes: [String: [String]]?

        /// ``EditableDocument/imports``.
        let imports: [String: String]?

        /// ``EditableDocument/variables``.
        let variables: [String: PenVariable]?

        /// ``EditableDocument/fonts``.
        let fonts: [PenFontDeclaration]?

        /// ``EditableDocument/extras``.
        let extras: PenExtras

        /// The basis of a settle of `document` for `theme`.
        ///
        /// - Parameters:
        ///   - document: The document being settled.
        ///   - theme: The theme axes pinned for the read.
        init(of document: EditableDocument, theme: [String: String]) {
            readContextSerial = document._readContextSerial
            self.theme = theme
            version = document.version
            themes = document.themes
            imports = document.imports
            variables = document.variables
            fonts = document.fonts
            extras = document.extras
        }
    }

    /// One root's share of a settled tree.
    struct Piece {
        /// The root's ``EditableDocument/revision(of:)`` when it was settled: a pin on its
        /// subtree and on every component it draws.
        let revision: String

        /// Its nodes' parent-relative rects.
        let rects: [String: PenRect]

        /// Its nodes' document-space rects.
        let absoluteRects: [String: PenRect]

        /// Its resolved nodes, children stripped.
        let nodes: [String: PenNode]
    }
}
