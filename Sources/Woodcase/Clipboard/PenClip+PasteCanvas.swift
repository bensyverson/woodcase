//
//  PenClip+PasteCanvas.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The definitions a paste inserts, placed in a row as roots past everything on the
    /// canvas: ``RootOverlap/margin`` to the right of the rightmost thing there, aligned
    /// with the topmost, each the margin after the one before — the rule
    /// ``BatchApplier`` places a copied root by, so a definition never lands on an
    /// artboard. On an empty canvas they keep the coordinates they were stored with.
    ///
    /// - Parameters:
    ///   - definitions: The definitions, in order.
    ///   - widths: Each one's width, as the clip lays it out.
    ///   - occupied: The canvas rects already taken: the target's roots, and the copies
    ///     when they land on the canvas.
    /// - Returns: The definitions, placed.
    static func pastTheCanvas(_ definitions: [PenNode], widths: [Double], occupied: [PenRect]) -> [PenNode] {
        guard let right = occupied.map({ $0.x + $0.width }).max(), let top = occupied.map(\.y).min() else {
            return definitions
        }
        var x = right + RootOverlap.margin
        return zip(definitions, widths).map { definition, width in
            var placed = definition
            placed.common.x = .literal(x)
            placed.common.y = .literal(top)
            x += width + RootOverlap.margin
            return placed
        }
    }

    /// The canvas rects the copies take once placed: each one's clip rect, moved to its
    /// new coordinates.
    ///
    /// - Parameters:
    ///   - placed: The copies, placed, in clip order.
    ///   - copied: The same copies as the clip holds them.
    ///   - rects: The clip's roots' rects, by clip id.
    /// - Returns: The rects.
    static func rects(of placed: [PenNode], sized copied: [PenNode], from rects: [String: PenRect]) -> [PenRect] {
        zip(placed, copied).compactMap { node, original in
            guard let rect = rects[original.id] else { return nil }
            let dx = (node.common.x?.literalValue ?? 0) - (original.common.x?.literalValue ?? 0)
            let dy = (node.common.y?.literalValue ?? 0) - (original.common.y?.literalValue ?? 0)
            return PenRect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
        }
    }

    /// The smallest rect holding every one of some rects, or `nil` for none.
    static func union(_ rects: [PenRect]) -> PenRect? {
        guard let minX = rects.map(\.x).min(), let minY = rects.map(\.y).min(),
              let maxX = rects.map({ $0.x + $0.width }).max(), let maxY = rects.map({ $0.y + $0.height }).max()
        else { return nil }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
