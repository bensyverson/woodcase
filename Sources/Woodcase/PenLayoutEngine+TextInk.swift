//
//  PenLayoutEngine+TextInk.swift
//  Woodcase
//

import CoreGraphics
import Foundation

extension PenLayoutEngine {
    /// The tight bounds of a text node's actual glyph ink, in its own box-local
    /// coordinates — zero-origin, the space ``ownInk(of:box:)`` reads every kind's
    /// geometry in.
    ///
    /// Pen's text node overrides `computeVisualLocalBounds` to return its Skia fill
    /// path's tight bounds, not its box (`project/2026-09-28-geometry-model.md`, "Pen's
    /// own code" for the text class): this is the same layout ``Woodcase/PenTextRenderer``
    /// draws, ``Woodcase/PenTextLayout``, whose ``Woodcase/PenTextLayout/inkBounds`` unions
    /// each line's glyph outline bounds (``outlineBounds(of:)``). An unbreakable word
    /// wider than its box, an italic's slant, or a paragraph that wraps past a fixed height
    /// all reach past the box on one axis or more — `PenPaintedExtentProbeTests`' x5–x7 hold three of Pen's exports to it.
    ///
    /// - Parameters:
    ///   - node: The text node; its runs are read from its metadata.
    ///   - box: Its box, in its own coordinates (zero-origin).
    /// - Returns: The tight ink bounds, or `nil` when there is no content to draw — Pen
    ///   draws nothing, so nothing paints.
    static func textInkBounds(of node: PenNode, box: PenRect) -> PenRect? {
        let size = CGSize(width: CGFloat(box.width), height: CGFloat(box.height))
        guard let ink = PenTextLayout(node, box: size)?.inkBounds else { return nil }
        return PenRect(x: Double(ink.minX), y: Double(ink.minY), width: Double(ink.width), height: Double(ink.height))
    }
}
