//
//  ArtboardLayout.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Where every node of one artboard sits, in the artboard's own coordinates — the map
/// the overlay draws boxes from.
///
/// Inlined into the page as JSON rather than fetched, so the first paint can already
/// outline the selected node and so an overlay never lags the image it is drawn over.
/// It is one struct, encoded once and read by the script: there is no hand-written
/// JavaScript twin of it to drift.
///
/// ## Why the engine's rects are not enough on their own
///
/// ``PenLayoutEngine`` reports each node's rect **in its parent's coordinate space**,
/// which is what the renderer wants (it translates by each rect as it descends) and not
/// what an absolutely-positioned `<div>` wants. ``of(artboard:in:scale:)`` takes the
/// composed frame from
/// ``Woodcase/PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` — the same walk
/// `woodcase shot --outline` places its boxes with — moves it to the artboard's own
/// corner with ``local(_:origin:)``, and walks the tree itself only for what the rects
/// cannot carry: document order, the name path, and each node's
/// ``Woodcase/TreeRow/Clip`` against its parent, which is a parent-*local* test.
///
/// ## Why a box's id is not always the expanded node's id
///
/// A click on the render selects whatever this map says it hit, so every id in it has to
/// be one the outline carries and the resolver accepts. Expansion does not quite give
/// that: it roots a component clone at `<ref>/<component root>` while the outline names
/// that row after the `ref` alone. `address(of:under:)` closes the gap, and is the one
/// place the two spellings are reconciled.
public struct ArtboardLayout: Friendly {
    /// Creates a layout.
    ///
    /// - Parameters:
    ///   - artboard: The artboard's node id.
    ///   - width: Its settled width in layout points.
    ///   - height: Its settled height in layout points.
    ///   - scale: Pixels per layout point the image was rendered at.
    ///   - revision: The document revision it was read at.
    ///   - nodes: Every node inside it, in document order.
    public init(
        artboard: String,
        width: Double,
        height: Double,
        scale: Double,
        revision: String,
        nodes: [Node]
    ) {
        self.artboard = artboard
        self.width = width
        self.height = height
        self.scale = scale
        self.revision = revision
        self.nodes = nodes
    }

    /// One node's box, in the artboard's coordinates.
    public struct Node: Friendly, Identifiable {
        /// Creates a box.
        ///
        /// - Parameters:
        ///   - id: The id a selection addresses this node by.
        ///   - path: Its name path, which is what a person hands to an agent.
        ///   - x: Its left edge, in points from the artboard's left.
        ///   - y: Its top edge, in points from the artboard's top.
        ///   - width: Its settled width in points.
        ///   - height: Its settled height in points.
        ///   - clip: How much of it falls outside its parent.
        public init(
            id: String,
            path: String,
            x: Double,
            y: Double,
            width: Double,
            height: Double,
            clip: TreeRow.Clip = .none
        ) {
            self.id = id
            self.path = path
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.clip = clip
        }

        /// The id a selection addresses this node by — the one ``OutlineRow`` puts on
        /// its row and ``Woodcase/EditableDocument/resolve(_:tags:)-(String,_)`` accepts.
        ///
        /// The same string as the node's id in the expanded document everywhere except an
        /// instance root; `address(of:under:)` says why those two differ and which wins.
        public let id: String
        /// Its name path.
        public let path: String
        /// Its left edge, in points from the artboard's left.
        public let x: Double
        /// Its top edge, in points from the artboard's top.
        public let y: Double
        /// Its settled width in points.
        public let width: Double
        /// Its settled height in points.
        public let height: Double
        /// How much of it falls outside its parent — the tree view's own geometric test,
        /// computed here from the parent-local rects so the selection footer can say
        /// "clipped" without a second read of the file.
        public let clip: TreeRow.Clip
    }

    /// The artboard's node id.
    public let artboard: String
    /// Its settled width in layout points.
    public let width: Double
    /// Its settled height in layout points.
    public let height: Double
    /// Pixels per layout point the image was rendered at.
    public let scale: Double
    /// The document revision it was read at.
    public let revision: String
    /// Every node inside it, in document order.
    public let nodes: [Node]

    /// The box for one node.
    ///
    /// - Parameter id: The id a selection addresses the node by — ``Node/id``, not
    ///   necessarily the id it carries in the expanded document.
    /// - Returns: Its box, or `nil` when the artboard does not contain it.
    public func node(id: String) -> Node? {
        nodes.first { $0.id == id }
    }

    /// The layout of one artboard of a prepared document.
    ///
    /// - Parameters:
    ///   - artboard: The artboard to map.
    ///   - prepared: The prepared document its rects came from.
    ///   - scale: Pixels per layout point the image was rendered at.
    /// - Returns: The layout, or `nil` when the document holds no such top-level frame.
    public static func of(
        artboard: Artboard,
        in prepared: PreparedDocument,
        scale: Double
    ) -> ArtboardLayout? {
        guard let root = prepared.document.children.first(where: { $0.id == artboard.id }) else {
            return nil
        }
        let placed = PenLayoutEngine.absoluteRects(
            under: artboard.id, in: prepared.document, layoutRects: prepared.rects
        )
        var nodes: [Node] = []
        collect(
            node: root, address: address(of: root.id, under: nil), path: [], parent: nil,
            placed: local(placed, origin: placed[artboard.id]),
            rects: prepared.rects, into: &nodes
        )
        return ArtboardLayout(
            artboard: artboard.id,
            width: artboard.width,
            height: artboard.height,
            scale: scale,
            revision: prepared.revision,
            nodes: nodes
        )
    }

    /// Moves a composed frame so it starts at the artboard's own top-left corner.
    ///
    /// ``Woodcase/PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` answers in the
    /// **root's** frame, and a top-level frame's own rect is in *canvas* coordinates: ask
    /// it for an artboard and every box comes back offset by where that artboard sits on
    /// the canvas. The image is drawn from the artboard's corner, so the boxes over it
    /// have to be too — an artboard at `x: 500` otherwise puts every one of its nodes
    /// past the right edge of a 200-point image, where the selection outline is invisible
    /// and no click can ever hit one. This is the subtraction `shot --outline` makes when
    /// it passes the rendered node's rect origin to its overlay.
    ///
    /// - Parameters:
    ///   - placed: The composed frame, in the artboard's canvas coordinates.
    ///   - origin: The artboard's own rect, or `nil` when the layout settled none — in
    ///     which case there is nothing to subtract and nothing to draw.
    /// - Returns: The same boxes, measured from the artboard's top-left corner.
    static func local(_ placed: [String: PenRect], origin: PenRect?) -> [String: PenRect] {
        guard let origin, origin.x != 0 || origin.y != 0 else { return placed }
        return placed.mapValues { rect in
            PenRect(x: rect.x - origin.x, y: rect.y - origin.y, width: rect.width, height: rect.height)
        }
    }

    /// Walks a subtree in document order, reading each node's box out of the composed
    /// frame and its clip out of the parent-local rects.
    ///
    /// - Parameters:
    ///   - node: The node to place.
    ///   - address: The id a selection addresses it by, from `address(of:under:)`.
    ///   - path: Its ancestors' names, outermost first.
    ///   - parent: The parent's settled size, or `nil` for the root of the walk.
    ///   - placed: The composed frame — every node's box in the artboard's coordinates.
    ///   - rects: The engine's parent-local rects, which the clip test reads.
    ///   - nodes: The boxes gathered so far.
    private static func collect(
        node: PenNode,
        address: String,
        path: [String],
        parent: (width: Double, height: Double)?,
        placed: [String: PenRect],
        rects: [String: PenRect],
        into nodes: inout [Node]
    ) {
        guard let rect = rects[node.id], let box = placed[node.id] else { return }
        let named = path + [node.common.name ?? "#\(node.id)"]
        nodes.append(Node(
            id: address,
            path: named.joined(separator: "/"),
            x: box.x,
            y: box.y,
            width: box.width,
            height: box.height,
            clip: clip(rect, in: parent)
        ))
        for child in node.kind.inlineChildren {
            collect(
                node: child,
                address: self.address(of: child.id, under: node.id),
                path: named,
                parent: Self.clipBox(of: node, rect: rect),
                placed: placed,
                rects: rects,
                into: &nodes
            )
        }
    }

    /// The id a selection addresses an expanded node by.
    ///
    /// Everywhere but one place this is the node's own expanded id, which is already the
    /// id-path the tree view prints and the resolver accepts (`Card1/Ttl03`). The
    /// exception is an instance **root**: ``Woodcase/PenRefExpander`` replaces a `ref`
    /// with a clone of its component and prefixes every id in the clone with the ref's,
    /// so the instance placed by `Card1` is rooted at `Card1/CardC` — a string that names
    /// no outline row and that
    /// ``Woodcase/EditableDocument/resolve(_:tags:)-(String,_)`` rejects outright, because
    /// a component root is not a step of an address. The row for that box is the `ref`,
    /// `Card1`, and so is the box's id here.
    ///
    /// A clone's root is exactly the node whose instance prefix is longer than its
    /// parent's, which is what this compares — no second walk of the authored tree, and
    /// no assumption about how deeply instances nest.
    ///
    /// - Parameters:
    ///   - id: The node's id in the expanded document.
    ///   - parent: Its parent's id in the expanded document, or `nil` at the root of the
    ///     walk, where the document itself is the parent and its prefix is empty.
    /// - Returns: The id to address the node by.
    static func address(of id: String, under parent: String?) -> String {
        let instance = instancePrefix(of: id)
        return instance == instancePrefix(of: parent ?? "") ? id : instance
    }

    /// The chain of `ref` ids an expanded node sits inside, as one string.
    ///
    /// - Parameter id: The node's id in the expanded document.
    /// - Returns: Everything before the last separator — empty in the document's own
    ///   tree.
    static func instancePrefix(of id: String) -> String {
        guard let slash = id.lastIndex(of: "/") else { return "" }
        return String(id[id.startIndex ..< slash])
    }

    /// The box a node's children are tested against by ``clip(_:in:)``: its settled size,
    /// or `nil` for a group, which has no box to clip them to and whose rect is their union
    /// measured from its anchor, so nothing under it is outside it.
    ///
    /// - Parameters:
    ///   - node: The parent.
    ///   - rect: Its settled rect.
    /// - Returns: The size to test its children against, or `nil`.
    static func clipBox(of node: PenNode, rect: PenRect) -> (width: Double, height: Double)? {
        if case .group = node.kind { return nil }
        return (rect.width, rect.height)
    }

    /// How much of a parent-local rect falls outside its parent's box.
    ///
    /// The tree view's own test, repeated here rather than shared because the tree
    /// view's copy works on a walk this one does not have: purely geometric, against
    /// `(0, 0, parent.width, parent.height)`, and `none` for a node with no parent.
    ///
    /// - Parameters:
    ///   - rect: The child's rect, in the parent's coordinates.
    ///   - parent: The parent's settled size, or `nil` for the root of the walk.
    /// - Returns: How much of it is outside.
    static func clip(_ rect: PenRect, in parent: (width: Double, height: Double)?) -> TreeRow.Clip {
        guard let parent else { return .none }
        let outside = rect.x >= parent.width || rect.y >= parent.height
            || rect.x + rect.width <= 0 || rect.y + rect.height <= 0
        if outside { return .full }
        let crosses = rect.x < 0 || rect.y < 0
            || rect.x + rect.width > parent.width || rect.y + rect.height > parent.height
        return crosses ? .partial : .none
    }
}
