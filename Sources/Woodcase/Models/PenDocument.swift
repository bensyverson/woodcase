//
//  PenDocument.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// The root of a .pen scene graph document.
///
/// A .pen file is a JSON document containing:
/// - A `version` string
/// - Optional `themes` (multi-axis theme dimensions)
/// - Optional `imports` (cross-file references)
/// - Optional `variables` (typed, theme-aware bindings)
/// - Optional `fileToken` (a per-save token the format's own editor writes)
/// - Optional `fonts` (font files the document ships — see ``PenFontDeclaration``)
/// - A `children` array of top-level nodes
/// - Any root key the model does not claim, kept verbatim in ``extras``
///
/// Woodcase models exactly one format version. A document parsed by ``PenParser``
/// from an older file reports ``currentFormatVersion`` — older files are rewritten by
/// ``PenLegacyMigrator`` on the way in — while one from a newer Pen keeps the
/// ``version`` it declared, so writing it back never downgrades it. See
/// ``formatRelation``.
public struct PenDocument: Friendly {
    /// The .pen format version Woodcase's model represents.
    public static let currentFormatVersion = PenFormatVersion.current.description

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - version: The .pen format version string.
    ///   - themes: Theme axes and their options.
    ///   - imports: Import aliases and the files they name.
    ///   - variables: Variable definitions by name.
    ///   - fileToken: The format's own editor's per-save token, if the file had one.
    ///   - fonts: The font files the document declares.
    ///   - children: The top-level nodes.
    ///   - extras: Root keys a file wrote that the model does not claim.
    public init(
        version: String = PenDocument.currentFormatVersion,
        themes: [String: [String]]? = nil,
        imports: [String: String]? = nil,
        variables: [String: PenVariable]? = nil,
        fileToken: String? = nil,
        fonts: [PenFontDeclaration]? = nil,
        children: [PenNode],
        extras: PenExtras = PenExtras()
    ) {
        self.version = version
        self.themes = themes
        self.imports = imports
        self.variables = variables
        self.fileToken = fileToken
        self.fonts = fonts
        self.children = children
        self.extras = extras
    }

    /// The .pen format version string: the model's for a document parsed from an
    /// older file, the declared one for a newer minor or another major.
    public var version: String

    /// Theme dimensions. Each key is a theme axis (e.g. "mode"), and the value is
    /// an array of options (e.g. ["light", "dark"]).
    public var themes: [String: [String]]?

    /// Import aliases mapping to file paths or URLs.
    public var imports: [String: String]?

    /// Variable definitions, keyed by variable name.
    public var variables: [String: PenVariable]?

    /// A per-save token the format's own editor stamps on every file it writes.
    ///
    /// It is not part of the published schema and carries no meaning for us:
    /// Woodcase preserves it when a file has one and never generates one.
    public var fileToken: String?

    /// The font files the document declares in its root `fonts` array, in the file's
    /// order, or `nil` when it declares none.
    ///
    /// A text node whose `fontFamily` is a declaration's ``PenFontDeclaration/name`` is
    /// meant to be set in that declaration's file, ahead of any system or Google font of
    /// the same name. Resolve a declaration's file with
    /// ``PenFontDeclaration/resolvedURL(relativeTo:)``, passing the .pen file's directory.
    public var fonts: [PenFontDeclaration]?

    /// The top-level nodes in the scene graph.
    public var children: [PenNode]

    /// Root keys the file wrote that the model does not claim, kept verbatim. See
    /// ``PenExtras``.
    public var extras: PenExtras
}
