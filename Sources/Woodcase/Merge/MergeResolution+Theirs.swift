//
//  MergeResolution+Theirs.swift
//  Woodcase
//

import Foundation

/// Whether a merge lands exactly on the external document.
extension MergeResolution {
    /// Whether the merged document equals `theirs`: every way the local document
    /// differs from it, the merge resolves to theirs' side.
    ///
    /// Costs one pruned walk from ours to theirs, so a merge that leaves no local work
    /// behind is told apart without applying anything.
    ///
    /// - Parameters:
    ///   - ours: The local document the resolution applies to.
    ///   - theirs: The external document.
    func reachesTheirs(ours: EditableDocument, theirs: EditableDocument) -> Bool {
        let gap = DocumentChanges(from: ours, to: theirs)
        for key in gap.document {
            switch key {
            case .rootOrder:
                guard rootOrder == theirs.rootOrder else { return false }
            default:
                guard document.contains(key) else { return false }
            }
        }
        for (id, change) in gap.nodes {
            switch change.existence {
            case .removed:
                guard removed.contains(id) else { return false }
            case .added, .kept:
                guard nodes[id] == change.to else { return false }
            }
        }
        return true
    }
}
