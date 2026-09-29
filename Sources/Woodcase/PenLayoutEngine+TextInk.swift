//
//  PenLayoutEngine+TextInk.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

extension PenLayoutEngine {
    /// The tight bounds of a text node's actual glyph ink, in its own box-local
    /// coordinates — zero-origin, the space ``ownInk(of:box:)`` reads every kind's
    /// geometry in.
    ///
    /// Pen's text node overrides `computeVisualLocalBounds` to return its Skia fill
    /// path's tight bounds, not its box (`project/2026-09-28-geometry-model.md`, "Pen's
    /// own code" for the text class): this lays out the same lines
    /// ``Woodcase/PenTextRenderer`` draws (``Woodcase/PenTextLines``, the same vertical
    /// alignment), asks each for its glyphs' outline bounds (``outlineBounds(of:)``), and
    /// unions them. An unbreakable word wider than its box, an italic's slant, or a
    /// paragraph that wraps past a fixed height all reach past the box on one axis or
    /// more — `PenPaintedExtentProbeTests`' x5–x7 hold three of Pen's exports to it.
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - box: Its box, in its own coordinates (zero-origin).
    /// - Returns: The tight ink bounds, or `nil` when there is no content to draw — Pen
    ///   draws nothing, so nothing paints.
    static func textInkBounds(of data: PenNode.TextData, box: PenRect) -> PenRect? {
        guard let built = PenTextRenderer.buildAttributedString(from: data, color: inkMeasuringColor)
        else { return nil }

        let size = CGSize(width: CGFloat(box.width), height: CGFloat(box.height))
        let lines = PenTextLines(
            built.string, width: size.width, pitch: built.pitch, firstBaseline: built.firstBaseline
        )
        // The same vertical alignment `PenTextRenderer.renderText` computes, so the ink
        // this measures is the ink that block actually draws.
        let verticalOffset: CGFloat = switch data.textAlignVertical {
        case .middle: (size.height - ceil(lines.height)) / 2
        case .bottom: size.height - ceil(lines.height)
        default: 0
        }
        let textSpace = CGAffineTransform(translationX: 0, y: verticalOffset + size.height)
            .scaledBy(x: 1, y: -1)

        var union: CGRect?
        for (line, origin) in lines.placed(inBoxOfHeight: size.height) {
            // The glyphs' outlines, as Pen's Skia fill path is measured; image bounds run loose.
            guard var bounds = outlineBounds(of: line) else { continue }
            bounds.origin.x += origin.x
            bounds.origin.y += origin.y
            let transformed = bounds.applying(textSpace)
            union = union.map { $0.union(transformed) } ?? transformed
        }
        guard let union else { return nil }
        return PenRect(x: Double(union.minX), y: Double(union.minY), width: Double(union.width), height: Double(union.height))
    }

    /// The color ``textInkBounds(of:box:)`` builds its measuring string with. Never
    /// drawn — any opaque color answers the same glyph geometry — so a plain black
    /// keeps the call site from having to invent one.
    private static let inkMeasuringColor = CGColor(gray: 0, alpha: 1)
}
