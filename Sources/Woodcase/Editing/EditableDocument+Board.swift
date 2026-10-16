//
//  EditableDocument+Board.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The board under a canvas point: the top-most top-level frame whose rect holds it,
    /// as a click there finds it — a component's own frame included — or `nil` over
    /// empty canvas.
    ///
    /// Only a frame is a board: a top-level group, instance, shape, text or note is
    /// passed over, so the board beneath one is found. Where boards overlap, the one
    /// drawn last — on top — wins. A rect holds its top and left edges, not its bottom
    /// and right, so two boards that touch never both hold a point.
    ///
    /// - Parameter point: A point on the canvas.
    /// - Returns: The board's id.
    func board(at point: PenPoint) -> String? {
        RootOverlap.roots(in: self).last { root in
            guard case .frame? = nodes[root.id]?.kind else { return false }
            let rect = root.rect
            return point.x >= rect.x && point.x < rect.x + rect.width
                && point.y >= rect.y && point.y < rect.y + rect.height
        }?.id
    }
}
