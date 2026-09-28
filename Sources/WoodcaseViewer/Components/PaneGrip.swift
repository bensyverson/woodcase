//
//  PaneGrip.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The draggable seam between two panes.
///
/// The panes are grid tracks whose sizes are custom properties on the container
/// (`--v-col-left`, `--v-row-lower`), so dragging is one property write and the browser
/// does the rest — no element is measured, positioned or resized by hand, and a grip
/// that fails to load leaves a layout with perfectly good defaults.
///
/// It is a real element rather than the grid's `gap` because a one-pixel line is not a
/// target: the grip is six pixels wide with the line drawn down its middle, so it looks
/// like a seam and behaves like a handle.
///
/// The size is remembered in `localStorage` by ``ViewerScript``, per grip and not per
/// file: how wide you like the outline is a fact about your screen, not about the
/// document, and having it change when you click through to another file would be
/// baffling.
public struct PaneGrip: HTML {
    /// Which way the grip moves.
    public enum Axis: String, Friendly {
        /// A vertical seam between two columns; dragging it changes a column's width.
        case columns
        /// A horizontal seam between two rows; dragging it changes a row's height.
        case rows

        /// The pointer axis a drag reads.
        public var pointer: String {
            self == .columns ? "x" : "y"
        }
    }

    /// Which of the grip's two neighbours the custom property sizes.
    ///
    /// Not cosmetic: it decides which way a drag runs. Widening the left column means
    /// dragging *right*; widening the right column means dragging *left*, because the
    /// track being sized is on the other side of the seam.
    public enum Edge: String, Friendly {
        /// The sized track is the grip's previous sibling.
        case before
        /// The sized track is the grip's next sibling.
        case after
    }

    /// Creates a grip.
    ///
    /// - Parameters:
    ///   - name: What to remember it as — the `localStorage` key's last component.
    ///   - property: The custom property on the grip's parent it writes.
    ///   - axis: Which way it moves.
    ///   - edge: Which neighbour the property sizes.
    public init(name: String, property: String, axis: Axis, edge: Edge) {
        self.name = name
        self.property = property
        self.axis = axis
        self.edge = edge
    }

    /// What to remember the grip as.
    public let name: String

    /// The custom property it writes on its parent.
    public let property: String

    /// Which way it moves.
    public let axis: Axis

    /// Which neighbour the property sizes.
    public let edge: Edge

    public var body: some HTML {
        div(
            .class("v-grip"),
            .data("grip", value: name),
            .data("property", value: property),
            .data("axis", value: axis.pointer),
            .data("edge", value: edge.rawValue),
            .custom(name: "role", value: "separator"),
            .custom(
                name: "aria-orientation",
                value: axis == .columns ? "vertical" : "horizontal"
            )
        ) { "" }
    }
}
