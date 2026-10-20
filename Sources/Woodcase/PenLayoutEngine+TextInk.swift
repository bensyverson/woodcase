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
    /// Setting the text and walking its outlines is most of what a painted-extent pass
    /// costs, so the ink is kept by ``TextInkCache`` — keyed by the text, its style, its
    /// runs and its box, and bound to the font set — and an unchanged text is measured once
    /// per process.
    ///
    /// - Parameters:
    ///   - node: The text node; its runs are read from its metadata.
    ///   - box: Its box, in its own coordinates (zero-origin).
    /// - Returns: The tight ink bounds, or `nil` when there is no content to draw — Pen
    ///   draws nothing, so nothing paints.
    static func textInkBounds(of node: PenNode, box: PenRect) -> PenRect? {
        CostCounter.record(.textInkLookup)
        guard case let .text(data) = node.kind, let text = data.content?.literalValue else { return nil }
        let key = TextInkCache.Key(
            text: text, style: PenTextStyle(data), runs: node.appliedRuns, width: box.width, height: box.height
        )
        return TextInkCache.current.inkBounds(of: key, measure: measuredInk)
    }

    /// A text's ink, set and outlined afresh: what ``textInkBounds(of:box:)`` answers when
    /// ``TextInkCache`` has not seen the text.
    private static func measuredInk(of key: TextInkCache.Key) -> PenRect? {
        CostCounter.record(.textInkLayout)
        let layout = PenTextLayout(
            text: key.text, style: key.style, runs: key.runs, box: CGSize(width: key.width, height: key.height)
        )
        guard let ink = layout.inkBounds else { return nil }
        return PenRect(x: Double(ink.minX), y: Double(ink.minY), width: Double(ink.width), height: Double(ink.height))
    }
}
