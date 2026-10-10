//
//  PenTextGeometry+Caret.swift
//  Woodcase
//

import Foundation

public extension PenTextGeometry {
    /// The line a caret index stands on.
    ///
    /// At a soft wrap the index ends one line and starts the next: `.upstream` answers the
    /// earlier line, `.downstream` the later. An index inside a cluster or a `\r\n` answers
    /// the line holding that cluster; one past the text answers the last line.
    ///
    /// - Parameters:
    ///   - index: A UTF-16 offset.
    ///   - affinity: The side of a soft wrap it is on.
    /// - Returns: An index into ``lines``.
    func lineIndex(containing index: Int, affinity: Affinity = .downstream) -> Int {
        let index = min(max(index, 0), length)
        let holding = lines.indices.filter { line in
            guard let first = lines[line].carets.first, let last = lines[line].carets.last else { return false }
            return first.index <= index && index <= last.index
        }
        if let line = affinity == .upstream ? holding.first : holding.last {
            return line
        }
        return lines.firstIndex { $0.stringRange.contains(index) } ?? lines.count - 1
    }

    /// The UTF-16 range of the characters on the line a caret index stands on, its newline
    /// included: what Home, End and a triple click reach.
    ///
    /// - Parameters:
    ///   - index: A UTF-16 offset.
    ///   - affinity: The side of a soft wrap it is on.
    /// - Returns: The line's string range; empty for a synthesized line.
    func lineRange(at index: Int, affinity: Affinity = .downstream) -> Range<Int> {
        lines[lineIndex(containing: index, affinity: affinity)].stringRange
    }

    /// The caret at an index: zero wide, its line's band tall, at the caret's x.
    ///
    /// An index inside a grapheme cluster stands at the cluster's start; one outside the
    /// text is clamped to it. Draw the caret at whatever width the editor draws carets,
    /// centered on the rect's x. A caret on a line past a fixed-height box lies past it.
    ///
    /// - Parameters:
    ///   - index: A UTF-16 offset.
    ///   - affinity: The side of a soft wrap it is on.
    /// - Returns: The caret's rect, box-local and y-down.
    func caretRect(at index: Int, affinity: Affinity = .downstream) -> PenRect {
        let line = lines[lineIndex(containing: index, affinity: affinity)]
        let clamped = min(max(index, 0), length)
        let caret = line.carets.last { $0.index <= clamped } ?? line.carets[0]
        return PenRect(x: caret.x, y: line.band.y, width: 0, height: line.band.height)
    }

    /// The carets of one line, in index order: for moving up or down while keeping a
    /// caret's x (``position(onLine:nearestX:)``).
    ///
    /// - Parameter line: An index into ``lines``.
    /// - Returns: The line's carets.
    func caretOffsets(onLine line: Int) -> [Line.Caret] {
        lines[line].carets
    }

    /// The caret on a line nearest an x: where a caret moved up or down onto that line
    /// lands, or where a click in its band puts it.
    ///
    /// The line's last caret at a soft wrap is `.upstream`, so a click past a wrapped
    /// line's end puts the caret at that end rather than at the next line's start.
    ///
    /// - Parameters:
    ///   - line: An index into ``lines``, clamped to them.
    ///   - x: The x, box-local.
    /// - Returns: The nearest caret's position.
    func position(onLine line: Int, nearestX x: Double) -> Position {
        let line = lines[min(max(line, 0), lines.count - 1)]
        var nearest = line.carets[0]
        for caret in line.carets.dropFirst() where abs(caret.x - x) < abs(nearest.x - x) {
            nearest = caret
        }
        let wraps = line.ending == .softWrap && nearest.index == line.stringRange.upperBound
        return Position(index: nearest.index, affinity: wraps ? .upstream : .downstream)
    }

    /// The caret position a point hits: the nearest caret on the line whose band holds
    /// the point's y.
    ///
    /// A point above the first band hits the first line and one below the last band the
    /// last line, so a drag past the text keeps selecting; a point beside a line hits its
    /// nearer end. The index is always at a grapheme-cluster boundary.
    ///
    /// - Parameter point: A box-local, y-down point.
    /// - Returns: The position the point hits.
    func index(at point: PenPoint) -> Position {
        let line = lines.firstIndex { point.y < $0.band.y + $0.band.height } ?? lines.count - 1
        return position(onLine: line, nearestX: point.x)
    }
}
