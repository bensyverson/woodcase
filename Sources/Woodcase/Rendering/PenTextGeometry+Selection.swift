//
//  PenTextGeometry+Selection.swift
//  Woodcase
//

import Foundation

public extension PenTextGeometry {
    /// The rects that paint a selection: one per line it touches, each filling the line's
    /// band between the selection's carets on that line.
    ///
    /// A selection that continues past a line's end — taking in its newline, or running on
    /// past a soft wrap — reaches the box's right edge, as `NSTextView` draws it; one that
    /// stops at a soft wrap ends at the line's last caret. So a selected blank line still
    /// shows — except flush with the
    /// right edge (a right-aligned blank line), where its rect is zero wide: it is still
    /// returned, so the editor knows the line is selected and may widen it. The bands tile, so
    /// the rects of different lines never overlap. The range's ends are widened to
    /// grapheme-cluster boundaries. Also the rects to underline marked text by, and the
    /// first one is what `firstRect(forCharacterRange:)` answers.
    ///
    /// One rect per line assumes the line runs one way; a line that mixes directions
    /// gets the span between its outermost selected carets.
    ///
    /// - Parameter range: The selected UTF-16 range.
    /// - Returns: The rects, box-local and y-down, top to bottom; empty for an empty range.
    func selectionRects(for range: Range<Int>) -> [PenRect] {
        let lower = max(range.lowerBound, 0), upper = min(range.upperBound, length)
        guard lower < upper else { return [] }
        var rects: [PenRect] = []
        for line in lines where line.stringRange.overlaps(lower ..< upper) {
            let inSelection = line.carets.filter { $0.index >= lower && $0.index <= upper }
            let first = line.carets.last { $0.index <= lower } ?? line.carets[0]
            let last = line.carets.first { $0.index >= upper } ?? line.carets[line.carets.count - 1]
            var xs = ([first, last] + inSelection).map(\.x)
            let reachesEdge = switch line.ending {
            case .hardBreak: upper >= line.stringRange.upperBound
            case .softWrap: upper > line.stringRange.upperBound
            case .endOfText: false
            }
            if reachesEdge {
                xs.append(box.width)
            }
            guard let minX = xs.min(), let maxX = xs.max(), maxX > minX || reachesEdge else { continue }
            rects.append(PenRect(x: minX, y: line.band.y, width: maxX - minX, height: line.band.height))
        }
        return rects
    }
}
