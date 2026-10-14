//
//  PasteTarget.swift
//  Woodcase
//

import Foundation

/// Where a paste puts a clip's copied roots (``PenClip/plan(into:at:)``).
///
/// Every case names stored nodes by their own ids, the ids ``EditableDocument/nodes``
/// holds: a paste writes into the store, so it cannot land inside an instance's
/// expansion.
public enum PasteTarget: Friendly {
    /// Into a container, after its last child.
    ///
    /// In a stack — a frame whose layout is not `none` — the copies join the flow and
    /// lose their `x` and `y`, which the layout would ignore. In a free container each
    /// keeps the offset it had in the parent it was copied out of (``PenClip/offsets``):
    /// pasted back into that parent it lands on its original, pasted into another it
    /// lands at the same place there. A copy with no offset — copied from the canvas, or
    /// from a clip written before offsets — keeps its canvas position instead, written in
    /// the container's coordinates, and so do all of them when any lacks one. When the
    /// copies would land wholly outside the container, they are centered in it.
    case inside(containerID: String)

    /// Beside a node, in the same parent, right after it.
    ///
    /// In a stack the copies join the flow at that index. Elsewhere — a free container,
    /// or the canvas when the node is a root — they are placed to the node's right,
    /// top-aligned with it: ``PenClip/besideGap`` away inside a container,
    /// ``RootOverlap/margin`` away on the canvas.
    case after(siblingID: String)

    /// On the canvas, as roots, centered on a point — an editor's viewport center.
    case canvas(center: PenPoint)

    /// On the canvas, as roots, at the coordinates they were copied from.
    case inPlace
}
