//
//  ScaleCapture.swift
//  Woodcase
//

import Foundation

/// A selection captured for a proportional scale: everything it draws, as it stood when
/// the scale began, so each step is planned from that start and never from the last step.
///
/// Scale multiplies a selection by one factor about an anchor point — proportionally only,
/// so no font is ever stretched (Penumbra spec §5, Ben's rulings of 2026-10-14 and
/// 2026-10-18). It descends into children, and it multiplies every length on the node:
///
/// - **geometry**: a member's position relative to the anchor; a descendant's position in
///   its parent; every fixed `width` and `height`, and the fallback of a `fit_content(…)` or
///   `fill_container(…)`. A path's geometry is drawn into its box, so it needs no rewrite.
/// - **text**: `fontSize` (the size it is drawn at, so an unset one is written as 16 × the
///   factor), `letterSpacing`, and each rich-text run's own size. A `lineHeight` is a
///   multiple of the size in this format, so it is never scaled.
/// - **strokes**: `strokeWidth`, uniform or per side, and the dash pattern and its offset.
/// - **shape and layout**: `cornerRadius`, `gap` and `padding`.
/// - **effects**: a shadow's offset, blur and spread; a layer blur's and a background
///   blur's radius.
/// - **notes, prompts and contexts**: the box and the text style together, as a note's own
///   resize scales them (spec §5.9).
///
/// It leaves alone what is not a length — rotation, flips, opacity, fills, line-height
/// multiples, an icon's weight — and every **sizing mode**: an `auto` text keeps fitting its
/// words, a `fixed-width` text keeps fitting its height, a `fill_container` keeps filling. A
/// value bound to a variable stays bound and is reported in ``ScalePlan/unscaled``.
///
/// A member its parent's layout places grows in its slot and writes no position; one placed
/// by its own `x`/`y` is moved so its every point lands where the scale about the anchor
/// sends it on the canvas, under a turned or flipped parent too. Inside a component
/// instance every write is an override on the instance, as ``EditPlanner`` routes it; the
/// component is unchanged.
///
/// ```swift
/// let capture = try ScaleCapture(nodeIDs: selection, in: document, layout: layout)  // at the press
/// let step = try capture.plan(factor: 1.4, around: pivot, in: document)             // each frame
/// let drawn = try document.previewNodes(for: step.operations)
/// try session.submit(.local(LocalEdit(operations: step.operations)))                // on release
/// ```
///
/// Capturing walks the selection's expanded subtrees once; planning a step only multiplies
/// and routes what was captured, so it is cheap enough to run on every display refresh.
public struct ScaleCapture: Friendly {
    /// One node the scale writes: a member or a descendant of one, as it was drawn.
    struct Entry: Friendly {
        /// How the scale moves a node.
        enum Position: Friendly {
            /// A member placed by its own `x`/`y`: its position is scaled about the anchor,
            /// carried into its parent's coordinates by this map from the canvas.
            case anchored(canvasToParent: PenLayoutEngine.PlaneTransform)
            /// A descendant placed by its own `x`/`y`: its position in its parent, which the
            /// scale scales about its own origin, is multiplied.
            case scaled
            /// A node its parent's layout places, or one placed nowhere: no position written.
            case kept
        }

        /// The node's id in the expanded document.
        var expandedID: String

        /// Where its edits are stored.
        var address: ResolvedNodeAddress

        /// Every value it holds that the scale multiplies, as drawn — overrides applied,
        /// variables not resolved — read at capture.
        var values: [Value]

        /// How it moves.
        var position: Position
    }

    /// The members' union on the canvas, in canvas coordinates: the box a nine-point
    /// ``ScaleAnchor`` is read on. Empty at the origin when no member is drawn.
    public let bounds: PenRect

    /// The top-most members, by their ids in the expanded document, in the order given. A
    /// node named inside another named node is part of that one, not a member of its own.
    public let memberIDs: [String]

    /// Every node the scale writes, members first in their subtrees' walk order.
    let entries: [Entry]

    /// Captures a selection as it is drawn.
    ///
    /// - Parameters:
    ///   - nodeIDs: The selection: stored ids, or the expanded ids an editor holds — an
    ///     instance's root (`<ref id>/<component root id>`) or a node inside one.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the members' canvas
    ///     placements are read from.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/noNodes`` for an empty selection
    ///   and ``EditRefusal/Code/addressNotFound`` for an id naming nothing.
    public init(nodeIDs: [String], in document: EditableDocument, layout: PenLayoutState) throws(EditRefusal) {
        guard !nodeIDs.isEmpty else {
            throw EditRefusal(code: .noNodes, address: "", message: "Select something to scale.")
        }
        let members = try Self.topMostMembers(nodeIDs, in: document, layout: layout)
        memberIDs = members.map(\.expandedID)
        bounds = Self.union(of: memberIDs, in: layout)
        entries = members.flatMap { Self.entries(for: $0, in: document, layout: layout) }
    }

    /// Plans one step: the edits that scale the captured selection by `factor` about
    /// `anchor`, from the state it was captured in.
    ///
    /// Each call starts from the capture, so planning 1.2, then 1.5, then 2 gives exactly
    /// what planning 2 alone gives: a live gesture never compounds its factors.
    ///
    /// - Parameters:
    ///   - factor: How much bigger: 2 doubles, 0.5 halves. A positive, finite number.
    ///   - anchor: The point that stays still, in canvas coordinates.
    ///   - document: The document the capture was made from, unchanged since — the
    ///     planner routes each write against it.
    /// - Returns: The edits and what was left unscaled. A factor of 1 plans nothing.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/outOfRange`` for a factor that is
    ///   not a positive finite number, or the refusal ``EditPlanner`` raises for a write.
    public func plan(
        factor: Double, around anchor: PenPoint, in document: EditableDocument
    ) throws(EditRefusal) -> ScalePlan {
        guard factor.isFinite, factor > 0 else {
            throw EditRefusal(
                code: .outOfRange,
                address: memberIDs.first ?? "",
                property: "factor",
                expected: "a positive number",
                message: "Scale by a positive number, such as 2 to double or 0.5 to halve; \(factor) is not one."
            )
        }
        // Rounding to a hundredth would otherwise rewrite a value held more finely.
        guard factor != 1 else { return ScalePlan(operations: []) }
        var scaler = ProportionalScaler(factor: factor)
        var operations: [EditOperation] = []
        var unscaled: [ScalePlan.BoundValue] = []
        for entry in entries {
            let properties = entry.scaledProperties(by: &scaler, around: anchor, unscaled: &unscaled)
            operations += try EditPlanner.routeWrites(properties, at: entry.address, in: document)
        }
        return ScalePlan(operations: operations, unscaled: unscaled)
    }

    /// Plans one step about one of the nine points of ``bounds``.
    ///
    /// - Parameters:
    ///   - factor: How much bigger, as ``plan(factor:around:in:)`` takes it.
    ///   - anchor: Which point of the members' union stays still.
    ///   - document: The document the capture was made from.
    /// - Returns: The edits and what was left unscaled.
    /// - Throws: What ``plan(factor:around:in:)`` throws.
    public func plan(
        factor: Double, anchor: ScaleAnchor, in document: EditableDocument
    ) throws(EditRefusal) -> ScalePlan {
        try plan(factor: factor, around: anchor.point(in: bounds), in: document)
    }
}
