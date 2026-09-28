//
//  ShotRect.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// One rectangle a `shot` run drew, reported on `--json`.
///
/// A screenshot whose landmarks are not numbered is a picture of an unknown place: the
/// caller can see that *something* is boxed, but cannot say which pixels belong to which
/// node, and so cannot turn what it sees into an address it can edit. Every rect a run
/// drew comes back here — the rendered node first, then one entry per `--outline` in the
/// order the flags were given — carrying both the id the rest of the CLI keys on and the
/// address the caller typed, so the next command needs no lookup.
///
/// Every ``rect`` is in the **rendered node's own coordinate space**, the space the
/// printed `rect=` establishes, which is what makes the run's `scale`, `gutterLeft`,
/// `gutterTop` and the documented formula enough to place any of them in the image:
///
/// ```text
/// pixel = (point − origin) × scale + gutter
/// ```
///
/// where `origin` is ``ShotOutput/rect``'s `x`/`y` — the region actually drawn, which
/// is the crop when `--crop` was given.
struct ShotRect: Friendly {
    /// Why this rect is in the list.
    enum Role: String, Friendly {
        /// The node that was rendered. Always the first entry, and always the node's
        /// *own* rect — not the sub-rectangle `--crop` narrowed the render to.
        case node

        /// A node `--outline` boxed.
        case outline
    }

    /// Whether this is the rendered node or one of its boxes.
    let role: Role

    /// The node's id, in the form ref expansion produces — what `tree --expand` prints
    /// and what `shot` accepts back.
    let id: String

    /// The address as the caller typed it: the `<node>` argument for ``Role/node``, the
    /// `--outline` value for ``Role/outline``.
    let address: String

    /// The node's name, or its `#id` marker when it has none — the same string printed
    /// in the box's tag.
    let name: String

    /// The node's layout rect, in points, in the rendered node's own coordinate space.
    let rect: PenRect

    /// The list one run reports: the rendered node, then each box in flag order.
    ///
    /// The node's entry carries the node's *own* rect, not the region a `--crop`
    /// narrowed the render to — that region is ``ShotOutput/rect``. Reporting only one of
    /// the two would leave a caller stepping a tile grid unable to say how much board is
    /// left to read.
    ///
    /// - Parameters:
    ///   - selection: The resolved addresses, which carry the ids and what the caller
    ///     typed.
    ///   - node: The rendered node's own layout rect.
    ///   - outlines: The boxes actually drawn, in the same order as `selection.outlines`.
    /// - Returns: One entry per rect drawn.
    static func list(
        for selection: ShotTargets.Selection,
        node: PenRect,
        outlines: [ShotOverlay.Target]
    ) -> [ShotRect] {
        let root = ShotRect(
            role: .node,
            id: selection.root.id,
            address: selection.root.address,
            name: selection.root.label,
            rect: node
        )
        return [root] + zip(selection.outlines, outlines).map { box, target in
            ShotRect(
                role: .outline,
                id: box.id,
                address: box.address,
                name: box.label,
                rect: target.rect
            )
        }
    }
}
