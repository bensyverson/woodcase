//
//  EditPlanner+Scale.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans a one-off proportional scale: the selection captured and scaled by `factor`
    /// about one of the nine points of its union — what an inspector's Scale field and
    /// `woodcase scale` do.
    ///
    /// The edits are ``ScaleCapture``'s; a live gesture keeps the capture and plans each
    /// step from it instead.
    ///
    /// - Parameters:
    ///   - nodeIDs: The selection: stored ids, or the expanded ids an editor holds.
    ///   - factor: How much bigger: 2 doubles, 0.5 halves.
    ///   - anchor: Which point of the selection's union stays still.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands.
    /// - Returns: The edits, to submit as one, and what was left unscaled.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planScale(
        nodeIDs: [String],
        by factor: Double,
        anchor: ScaleAnchor,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> ScalePlan {
        try ScaleCapture(nodeIDs: nodeIDs, in: document, layout: layout).plan(
            factor: factor, anchor: anchor, in: document
        )
    }
}
