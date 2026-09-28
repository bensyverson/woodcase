//
//  Artboard.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One top-level frame of a document — what the viewer shows as a page.
///
/// Artboards are read from the *expanded and resolved* document, exactly as
/// `woodcase render` picks the frames it writes files for. That means a top-level
/// component instance is an artboard too, under the path id expansion gives it
/// (`YGJ0d/nSNTs`) — which is how a file's themed variants show up in the list.
///
/// The size is the settled rect, not the authored one: a frame written as
/// `fill_container` has no width in the file and a real width on screen.
///
/// ``x`` and ``y`` are where the frame sits **on the canvas**, which is the one piece of
/// geometry no single artboard's own view needs and the bird's-eye map is made of: the
/// map draws every artboard as a box at its document position, so a file's layout on the
/// canvas is what you navigate by.
public struct Artboard: Friendly, Identifiable {
    /// Creates an artboard.
    ///
    /// - Parameters:
    ///   - id: The node id, as the layout engine and the tree view spell it.
    ///   - name: The frame's name, or `nil` for an unnamed frame.
    ///   - x: Its left edge on the canvas, in layout points.
    ///   - y: Its top edge on the canvas, in layout points.
    ///   - width: The settled width in layout points.
    ///   - height: The settled height in layout points.
    ///   - isReusable: Whether this artboard is a reusable component definition.
    ///   - isInstance: Whether this artboard is a placed component instance — a
    ///     top-level `ref`, expanded to the id-path (`YGJ0d/nSNTs`) that marks it.
    ///   - isSlot: Whether this artboard is itself a slot frame.
    public init(
        id: String,
        name: String?,
        x: Double = 0,
        y: Double = 0,
        width: Double,
        height: Double,
        isReusable: Bool = false,
        isInstance: Bool = false,
        isSlot: Bool = false
    ) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isReusable = isReusable
        self.isInstance = isInstance
        self.isSlot = isSlot
    }

    /// The node id, which is also the `{artboard}` in its URL.
    ///
    /// An id containing a slash must be percent-encoded into the path.
    public let id: String

    /// The frame's name, or `nil` for an unnamed frame.
    public let name: String?

    /// Its left edge on the canvas, in layout points.
    ///
    /// Canvas coordinates, not the artboard's own: the layout engine reports a
    /// top-level frame's rect in the root's frame, and that rect *is* the canvas
    /// position. Every box inside the artboard is measured from its corner instead
    /// (see ``ArtboardLayout``); this is the corner.
    public let x: Double

    /// Its top edge on the canvas, in layout points.
    public let y: Double

    /// The settled width in layout points.
    public let width: Double

    /// The settled height in layout points.
    public let height: Double

    /// Whether this artboard is a reusable component definition — what
    /// ``TreeRow/isReusable`` marks on the same node.
    public let isReusable: Bool

    /// Whether this artboard is a placed component instance.
    ///
    /// Expansion prefixes a `ref`'s id with the ref node's own id (`PenRefExpander`), so
    /// an instance artboard's ``id`` always contains a slash; a definition or a plain
    /// frame's never does, because node ids are short alphanumeric strings with none.
    public let isInstance: Bool

    /// Whether this artboard is itself a slot frame.
    public let isSlot: Bool

    /// The longer of the two sides, which is what a size cap applies to.
    public var longestSide: Double {
        max(width, height)
    }

    /// The artboard that stands for a whole file — what a dashboard card shows and what
    /// the render cache warms a thumbnail of.
    ///
    /// A file is represented by a *screen*, not by a part of one, so a reusable
    /// definition and a slot are passed over: a card showing the 60×24 "Button"
    /// component tells a person nothing about which file they are looking at. A placed
    /// instance is kept, because an instance is a screen — that is how a file's themed
    /// variants (`YGJ0d/nSNTs`, "banking-home / Dark") come to be the cover of a file
    /// whose every definition is a component.
    ///
    /// When a file is *only* definitions — the shape a component library has — the first
    /// one is the answer rather than nothing: a thumbnail of a part beats an empty box.
    ///
    /// - Parameter artboards: The file's artboards, in document order.
    /// - Returns: The artboard to show, or `nil` when the file has none.
    public static func cover(of artboards: [Artboard]) -> Artboard? {
        artboards.first { !$0.isReusable && !$0.isSlot } ?? artboards.first
    }
}
