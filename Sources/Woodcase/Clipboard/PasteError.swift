//
//  PasteError.swift
//  Woodcase
//

import Foundation

/// Why ``PenClip/plan(into:at:)`` refuses a paste.
public enum PasteError: Error, Friendly, CustomStringConvertible {
    /// The clip names a copied root it does not hold: one of ``PenClip/contentIDs`` is
    /// not a root of ``PenClip/document``.
    case contentNotInClip(id: String)

    /// The target names a node the document does not store.
    case targetNotFound(id: String)

    /// ``PasteTarget/inside(containerID:)`` names a node that cannot hold children: a
    /// leaf such as a rectangle or a text, or an instance, whose children are its
    /// component's.
    case notAContainer(id: String)

    /// The paste would make components contain each other (``ComponentLoop``): it puts an
    /// instance inside a component that the instance renders, directly or through others.
    /// The loop is named in render order, starting from the component pasted into.
    case wouldCloseComponentLoop(ComponentLoop)

    /// The target names a node inside an instance that the slot planner refuses to paste
    /// at: one outside the instance's slots (``EditRefusal/Code/insideInstance``), or a
    /// fill it cannot read (``EditRefusal/Code/documentRefused``). The refusal says which.
    case slotRefused(EditRefusal)

    /// The refusal as a sentence.
    public var description: String {
        switch self {
        case let .contentNotInClip(id):
            "The clip lists \(id) as copied content, but holds no root with that id."
        case let .targetNotFound(id):
            "Nothing to paste into: no node has the id \(id)."
        case let .notAContainer(id):
            "\(id) cannot hold children, so nothing can be pasted inside it; "
                + "paste beside it or into its parent instead."
        case let .wouldCloseComponentLoop(loop):
            "Pasting here would make components contain each other: \(loop). "
                + "Paste outside the component, or paste a copy without that instance."
        case let .slotRefused(refusal):
            refusal.message
        }
    }
}
