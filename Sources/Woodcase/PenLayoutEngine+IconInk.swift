//
//  PenLayoutEngine+IconInk.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

extension PenLayoutEngine {
    /// The tight bounds of an icon node's actual glyph ink, in its own box-local
    /// coordinates — zero-origin, the space ``ownInk(of:box:)`` reads every kind's
    /// geometry in.
    ///
    /// Pen's icon node overrides `computeVisualLocalBounds` to return `fillPath.bounds`
    /// — its vector glyph, fitted to the box by its *shorter* side and centered, then
    /// measured tightly — not the box (`project/2026-09-28-geometry-model.md`, "Pen's
    /// own code" for the icon class, `DJt`). This measures the exact glyph
    /// ``Woodcase/PenIconGlyph`` builds for ``Woodcase/PenIconFontRenderer`` to draw —
    /// same face, same size, same position — so the ink this reports is the ink that
    /// glyph actually paints, via Core Text's image bounds
    /// (`CTLineGetImageBounds`) rather than a second, separate measurement.
    ///
    /// - Parameters:
    ///   - data: The icon node's data.
    ///   - box: Its box, in its own coordinates (zero-origin).
    /// - Returns: The tight ink bounds, or `nil` when the node names no library or icon,
    ///   or a library Woodcase has no font for — nothing is drawn.
    static func iconInkBounds(of data: PenNode.IconData, box: PenRect) -> PenRect? {
        let size = CGSize(width: CGFloat(box.width), height: CGFloat(box.height))
        guard let glyph = PenIconGlyph(data: data, box: size) else { return nil }
        let attributes: [CFString: Any] = [kCTFontAttributeName: glyph.font]
        guard let attributedString = CFAttributedStringCreate(
            kCFAllocatorDefault, glyph.string as CFString, attributes as CFDictionary
        ) else { return nil }
        let line = CTLineCreateWithAttributedString(attributedString)
        guard var bounds = Self.outlineBounds(of: line) else { return nil }

        // The same y-up draw position `PenIconFontRenderer` sets as `context.textPosition`,
        // in the space flipped from this box's own top-left, y-down coordinates.
        let drawPosition = CGPoint(x: glyph.origin.x, y: size.height - glyph.origin.y)
        bounds.origin.x += drawPosition.x
        bounds.origin.y += drawPosition.y
        let boxSpace = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
        let transformed = bounds.applying(boxSpace)
        return PenRect(
            x: Double(transformed.minX), y: Double(transformed.minY),
            width: Double(transformed.width), height: Double(transformed.height)
        )
    }

    /// The tight bounds of a line's glyph outlines, in its own y-up space, or `nil` when
    /// it draws nothing.
    ///
    /// `CTLineGetImageBounds` without a context reports a looser box for some icon fonts:
    /// Lucide's "minus", a bar 26 pt wide and 2.5 pt tall in a 40 pt box, came back
    /// 33.5 × 22 (`geometry-probe` x9). The outline is what Pen's `fillPath.bounds` measures.
    static func outlineBounds(of line: CTLine) -> CGRect? {
        var union: CGRect?
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as? [CFString: Any] ?? [:]
            guard let font = attributes[kCTFontAttributeName].map({ $0 as! CTFont }) else { continue }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var placement = CGAffineTransform(translationX: position.x, y: position.y)
                guard let path = CTFontCreatePathForGlyph(font, glyph, &placement), !path.isEmpty else { continue }
                let box = path.boundingBoxOfPath
                union = union.map { $0.union(box) } ?? box
            }
        }
        return union
    }
}
