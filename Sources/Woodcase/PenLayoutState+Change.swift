//
//  PenLayoutState+Change.swift
//  Woodcase
//

import Foundation

extension PenLayoutState {
    /// What differs between two rect maps among the ids a pass could have touched.
    ///
    /// - Parameters:
    ///   - before: The rects the pass started from.
    ///   - after: The rects it left.
    ///   - candidates: Every id whose rect the pass wrote or dropped; no other id differs.
    ///   - index: The tree `after` belongs to.
    ///   - oldIndex: The tree `before` belongs to.
    /// - Returns: The change, without ``PenLayoutChange/affectedRoots`` or stats.
    static func change(
        from before: [String: PenRect],
        to after: [String: PenRect],
        among candidates: Set<String>,
        index: PenLayoutIndex,
        oldIndex: PenLayoutIndex
    ) -> PenLayoutChange {
        var change = PenLayoutChange()
        for id in candidates {
            let old = before[id]
            let new = after[id]
            guard old != new else { continue }
            guard let new else {
                change.removed.insert(id)
                continue
            }
            change.rects[id] = new
            if let old, old.width == new.width, old.height == new.height, old.unturnedSize == new.unturnedSize {
                change.moved.insert(id)
            } else {
                change.resized.insert(id)
            }
        }
        change.topmost = topmost(of: change, index: index, oldIndex: oldIndex)
        return change
    }

    /// The changed subtrees' roots: every changed node, and every surviving parent of a
    /// removed one, that has no such node above it.
    private static func topmost(
        of change: PenLayoutChange, index: PenLayoutIndex, oldIndex: PenLayoutIndex
    ) -> Set<String> {
        var changed = Set(change.rects.keys)
        for id in change.removed {
            if let parent = oldIndex[id]?.parent, index[parent] != nil, !change.removed.contains(parent) {
                changed.insert(parent)
            }
        }
        return changed.filter { id in
            !index.ancestors(of: id).contains(where: changed.contains)
        }
    }
}
