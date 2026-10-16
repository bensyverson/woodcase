//
//  PasteTarget.swift
//  Woodcase
//

import Foundation

/// Where a paste puts a clip's copied roots (``PenClip/plan(into:at:)``).
///
/// Every case names stored nodes by their own ids, the ids ``EditableDocument/nodes``
/// holds: a paste writes into the store, so it cannot land inside an instance's
/// expansion. Every case that names a container refuses one the document does not store
/// (``PasteError/targetNotFound(id:)``) or one that cannot hold children
/// (``PasteError/notAContainer(id:)``), and in a stack — a frame whose layout is not
/// `none` — puts the copies in its flow, without `x` and `y`, which the layout would
/// ignore. Choosing *which* target a gesture means is the editor's; the geometry is
/// here, with ``EditableDocument/board(at:)`` for "the board under a point".
///
/// Wherever a copy lands, a dimension that filled its container where it was copied
/// fills again when the new parent lays the copy out, and is written at its drawn size
/// when it does not (``PenClip/Origin/width``).
///
/// Only ``inside(containerID:)`` ever moves copies to fit a container. Every other case
/// lands exactly where it says, outside the container's box or not, so a container that
/// clips shows what falls inside it.
public enum PasteTarget: Friendly {
    /// Into a container, after its last child.
    ///
    /// In a free container each copy keeps the offset it had in the parent it was copied
    /// out of (``PenClip/Origin/offset``): pasted back into that parent it lands on its
    /// original, pasted into another it lands at the same place there. A copy with no
    /// offset — copied from the canvas, or from a clip without origins — keeps its canvas
    /// position instead, written in the container's coordinates, and so do all of them
    /// when any lacks one. When the copies would land wholly outside the container, they
    /// are centered in it.
    case inside(containerID: String)

    /// Beside a node, in the same parent, right after it.
    ///
    /// In a stack the copies join the flow at that index. Elsewhere — a free container,
    /// or the canvas when the node is a root — they are placed to the node's right,
    /// top-aligned with it: ``PenClip/besideGap`` away inside a container,
    /// ``RootOverlap/margin`` away on the canvas.
    case after(siblingID: String)

    /// The copies' bounds — all of them together, as the clip lays them out — with their
    /// top-left corner on a canvas point, each copy keeping its place among the others:
    /// into a container, after its last child, or as roots when `in` is `nil`.
    ///
    /// The point is written in the container's coordinates, and the copies keep their
    /// arrangement along its axes, so in a turned container they turn with it. What an
    /// editor's pointer places a paste by.
    case at(topLeft: PenPoint, in: String?)

    /// The copies' bounds centered on a canvas point, each copy keeping its place among
    /// the others: into a container, after its last child, or as roots when `in` is
    /// `nil` — an editor's viewport center.
    case centered(on: PenPoint, in: String?)

    /// Into a container, after its last child, the copies' bounds with their top-left
    /// corner at the container's inner top-left: its box's corner moved in by its
    /// padding. Where something with no position of its own to keep — pasted plain
    /// text — lands in a free container.
    case atInnerTopLeft(of: String)

    /// Into a container, after its last child, each copy at the offset it had from its
    /// own board's top-left corner (``PenClip/Origin/boardOffset``) — from the canvas
    /// origin for a copy taken from the top level, and its canvas position for one
    /// without an origin. Paste in Place into another board.
    case atBoardOffset(in: String)

    /// Each copy back where it came from (``PenClip/origins``), on its own:
    ///
    /// - **Copied from the top level**: a root again, where it was. The canvas is in every
    ///   document, so this holds in another document too.
    /// - **Its parent is here**: when `documentID` equals the clip's
    ///   ``PenClip/sourceDocumentID`` — both given — and that parent is still a container
    ///   in this document, back into it at its offset there (in a stack, in the flow), and
    ///   at its place among the children: right after its source node while that is still
    ///   there, as Duplicate puts it, else at the index it had, clamped to the children
    ///   there now. A copy from the top level keeps its place among the roots the same
    ///   way.
    /// - **Otherwise** — another document, a parent deleted since, a node drawn inside an
    ///   instance, or a clip without origins — at the canvas position it was copied from,
    ///   inside the board under its center (``EditableDocument/board(at:)``, the top-most
    ///   where boards overlap), or as a root when no board is there.
    ///
    /// Paste in Place with nothing to anchor it.
    case whereCopied(documentID: String?)

    /// On the canvas, as roots, at the coordinates they were copied from.
    case inPlace
}
