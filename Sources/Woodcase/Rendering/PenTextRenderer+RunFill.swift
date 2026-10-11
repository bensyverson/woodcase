//
//  PenTextRenderer+RunFill.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

public extension PenTextRenderer {
    /// The attribute that marks a run whose glyphs take a fill of their own
    /// (``PenTextRun/fill``) rather than the node's paint.
    ///
    /// On the solid route the run's color is simply its Core Text color. On the
    /// glyph-outline route (a gradient, an image, a stack) the node's paint is drawn through
    /// the glyphs' outlines, so a marked run is kept out of that clip and drawn by Core Text
    /// in its own color, its bars with it (``PenGlyphOutlines/colorRuns``). Public so that
    /// another renderer (RapidPro) draws a colored run the same way.
    static var runFillKey: CFString {
        "WoodcaseRunFill" as CFString
    }

    /// Whether a run carries a fill of its own (``runFillKey``).
    ///
    /// - Parameter run: A run of a line built by ``PenTextLayout``.
    /// - Returns: `true` when the run's color is its own, not the node's paint.
    static func hasOwnFill(_ run: CTRun) -> Bool {
        (CTRunGetAttributes(run) as NSDictionary)[runFillKey] != nil
    }
}
