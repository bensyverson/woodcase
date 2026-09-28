//
//  EditableDocument+RevisionCoverage.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Every node whose content a node's ``revision(of:)`` folds in — what the token
    /// actually pins.
    ///
    /// The node itself, its descendants, and — through each `ref` — the components it
    /// renders and everything inside those, transitively. This is the set an edit has to
    /// fall inside to move the node's revision, which is what makes it the right
    /// question to ask of the activity log when a guard has failed: *whose* write moved
    /// my premise?
    ///
    /// A component graph may cycle; the walk visits each node once, so it terminates on
    /// one that does.
    ///
    /// - Parameter nodeID: The node whose revision is in question.
    /// - Returns: The ids the revision covers, including `nodeID` itself. Empty for a
    ///   node that is not in the document.
    func revisionCoverage(of nodeID: String) -> Set<String> {
        var covered: Set<String> = []
        var pending = [nodeID]
        while let current = pending.popLast() {
            guard let node = nodes[current], covered.insert(current).inserted else { continue }
            pending.append(contentsOf: children[current] ?? [])
            pending.append(contentsOf: componentsRendered(by: node))
        }
        return covered
    }
}
