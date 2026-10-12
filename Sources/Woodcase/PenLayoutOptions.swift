//
//  PenLayoutOptions.swift
//  Woodcase
//

import Foundation

/// What a caller lays a document out with beyond the document itself: the notes,
/// prompts and contexts it draws raw.
///
/// An editor draws the card being edited raw — its markdown as written, in the card's
/// text style (``PenPostIt/BodyText/raw``) — and the card grows to fit that text too:
/// its height is the most of its set height, its styled text's and its raw text's (Ben's
/// ruling 2026-10-12). Every ``PenLayoutEngine`` entry point and ``PenLayoutState`` take
/// one; the default draws every body styled, so a caller that draws nothing raw passes
/// nothing.
///
/// It is the layout's half of ``PenPostIt/DrawingOptions``, which a renderer takes:
/// ``PenPostIt/DrawingOptions/layoutOptions`` hands layout the same raw cards. It is a
/// separate value because layout must compare one set of options with the next —
/// rawness changes a card's height, so a change of it is an invalidation
/// (``invalidation(from:)``) — and drawing options hold the caller's functions, which
/// cannot be compared.
public struct PenLayoutOptions: Friendly {
    /// The ids of the notes, prompts and contexts drawn raw, by expanded id — the ids
    /// ``PenPostIt/DrawingOptions/rawBodies`` names. An id that names another kind of
    /// node, or nothing, changes nothing.
    public var rawBodies: Set<String>

    /// Creates layout options.
    ///
    /// - Parameter rawBodies: The ids of the cards drawn raw. Defaults to none.
    public init(rawBodies: Set<String> = []) {
        self.rawBodies = rawBodies
    }

    /// How a node's body is laid out under these options.
    ///
    /// - Parameter id: The node's expanded id.
    /// - Returns: ``PenPostIt/BodyText/raw`` for an id in ``rawBodies``, otherwise
    ///   ``PenPostIt/BodyText/styled``.
    public func bodyText(for id: String) -> PenPostIt.BodyText {
        rawBodies.contains(id) ? .raw : .styled
    }

    /// What changing from other options to these requires laying out again: every card
    /// that started or stopped being drawn raw, with its ancestors.
    ///
    /// A host that keeps its own measurement cache merges it into the document's
    /// invalidation (``PenLayoutInvalidation/union(_:)``) when the cards it draws raw
    /// change — a card enters or leaves editing. ``PenLayoutState`` works it out itself.
    ///
    /// - Parameter previous: The options of the last layout.
    /// - Returns: The cards whose rawness differs, as ``PenLayoutInvalidation/nodes``.
    public func invalidation(from previous: PenLayoutOptions) -> PenLayoutInvalidation {
        PenLayoutInvalidation(nodes: rawBodies.symmetricDifference(previous.rawBodies))
    }
}
