//
//  PenFontDeclaration.swift
//  Woodcase
//

import Foundation

/// One font file a document declares in its root `fonts` array.
///
/// A .pen file can ship its own fonts: each entry names a family and points at a font
/// file, optionally saying which style and weights that file covers. A text node whose
/// `fontFamily` is ``name`` is meant to be set in that file, ahead of any system or
/// Google font of the same name.
///
/// ```json
/// "fonts": [
///   {"name": "Brand Sans", "url": "fonts/BrandSans.ttf"},
///   {"name": "Brand Sans", "url": "fonts/BrandSans-Italic.ttf", "style": "italic", "weight": [100, 900]}
/// ]
/// ```
///
/// The keys and their forms are the ones Pen's own validator accepts: ``name`` and
/// ``url`` are strings, ``style`` is `normal` or `italic`, and ``weight`` is one number
/// or a `[min, max]` pair for a variable font; any other key is refused. Pen drops an
/// entry with no name or no url when it opens the file. See <doc:PenEngine>.
///
/// Woodcase carries the declaration through every edit, and registers its file ahead of
/// Google Fonts on every read and render — see <doc:PenGoogleFonts>.
public struct PenFontDeclaration: Friendly {
    /// Creates a declaration.
    ///
    /// - Parameters:
    ///   - name: The family name a text node's `fontFamily` refers to.
    ///   - url: Where the font file is, as the file writes it.
    ///   - style: Which style the file covers; `nil` is upright.
    ///   - weight: Which weight, or weights, the file covers; `nil` is the regular weight.
    ///   - extras: Keys the file wrote on this declaration that the model does not claim.
    public init(
        name: String,
        url: String,
        style: Style? = nil,
        weight: Weight? = nil,
        extras: PenExtras = PenExtras()
    ) {
        self.name = name
        self.url = url
        self.style = style
        self.weight = weight
        self.extras = extras
    }

    /// The family name a text node's `fontFamily` refers to.
    public var name: String

    /// Where the font file is, as the file writes it: a path relative to the .pen file,
    /// an absolute path, or a URL. ``resolvedURL(relativeTo:)`` turns it into a `URL`.
    public var url: String

    /// Which style the file covers. Absent means ``Style/normal``.
    public var style: Style?

    /// Which weight, or range of weights, the file covers. Absent means the regular
    /// weight, ``regularWeight``.
    public var weight: Weight?

    /// Keys the file wrote on this declaration that the model does not claim. See ``PenExtras``.
    public var extras: PenExtras

    /// The weight a declaration with no ``weight`` covers: CSS `normal`.
    public static let regularWeight: Double = 400

    /// The weights this file covers, lowest first: one weight, a variable font's whole
    /// range, or ``regularWeight`` when the declaration names none.
    public var weightRange: ClosedRange<Double> {
        switch weight {
        case let .single(value): value ... value
        case let .range(from, to): min(from, to) ... max(from, to)
        case nil: Self.regularWeight ... Self.regularWeight
        }
    }

    // MARK: - Style

    /// The style a font file covers.
    public enum Style: String, Friendly, CaseIterable {
        /// Upright.
        case normal
        /// Italic.
        case italic
    }

    // MARK: - Weight

    /// The weight a font file covers: one, or a variable font's range.
    ///
    /// Written as a number, or as a two-number array. A range is kept in the order the
    /// file wrote it; ``PenFontDeclaration/weightRange`` puts it lowest first.
    public enum Weight: Friendly {
        /// One weight, such as `700`.
        case single(Double)
        /// The range a variable font covers, such as `[100, 900]`.
        case range(from: Double, to: Double)
    }
}
