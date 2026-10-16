//
//  PasteSite+Positioning.swift
//  Woodcase
//

import Foundation

extension PasteSite {
    /// What the planner knows of the copied roots, in clip order, beside the roots
    /// themselves.
    struct Copies: Friendly {
        /// Each root's rect on the canvas, as the clip lays them out.
        var rects: [PenRect?]

        /// Each root's origin (``PenClip/origins``); `nil` for one the clip has none for.
        var origins: [PenClip.Origin?]

        /// The document the clip was copied out of (``PenClip/sourceDocumentID``).
        var sourceDocumentID: String?
    }

    /// The target laid out as the canvas draws it.
    struct Layout: Friendly {
        /// The target, expanded and resolved.
        var document: PenDocument

        /// Every drawn node's rect in its parent's coordinates, by expanded id.
        var rects: [String: PenRect]

        /// Lays out a document.
        init(of document: EditableDocument) {
            self.document = PenVariableResolver.resolve(document.expanded(for: .canvas))
            rects = PenLayoutEngine.layout(self.document)
        }

        /// Where a stored node is drawn on the canvas, or `nil` when it is not drawn.
        func placement(of id: String, in document: EditableDocument) -> PenPlacement? {
            PenLayoutEngine.canvasPlacement(
                of: document.expandedID(of: .node(id: id)), in: self.document, layoutRects: rects
            )
        }

        /// A canvas point in a stored node's own coordinates, or `nil` when it is not
        /// drawn or its placement cannot be undone.
        func local(_ point: PenPoint, in id: String, of document: EditableDocument) -> PenPoint? {
            placement(of: id, in: document)?.transform.inverted()?.apply(to: point)
        }
    }

    /// The copied roots, positioned for this site, each with where it is inserted.
    ///
    /// - Parameters:
    ///   - roots: The copied roots, carrying the canvas coordinates they were copied at.
    ///   - copies: What the clip knows of them, in the same order.
    ///   - document: The target document.
    /// - Returns: The roots, placed, in the same order.
    func placed(_ roots: [PenNode], copies: Copies, in document: EditableDocument) -> [Placed] {
        if case let .whereCopied(documentID) = arrangement {
            let home = documentID != nil && documentID == copies.sourceDocumentID
            return Self.whereCopied(roots, copies: copies, home: home, in: document)
        }
        return positioned(roots, copies: copies, in: document).enumerated().map { offset, node in
            Placed(node: node, parentID: parentID, index: index.map { $0 + offset })
        }
    }

    /// The roots positioned for a site that puts every one in the same parent.
    private func positioned(_ roots: [PenNode], copies: Copies, in document: EditableDocument) -> [PenNode] {
        let bounds = PenClip.union(copies.rects.compactMap(\.self))
        switch arrangement {
        case .asCopied, .whereCopied:
            return roots
        case .flow:
            return roots.map { root in
                var placed = root
                placed.common.x = nil
                placed.common.y = nil
                return placed
            }
        case let .container(id):
            return inContainer(
                roots, bounds: bounds, rects: copies.rects, offsets: copies.origins.map { $0?.offset },
                container: id, in: document
            )
        case let .beside(id, gap):
            guard let bounds, let sibling = Self.rect(of: id, in: document) else { return roots }
            return Self.shifted(roots, by: PenPoint(
                x: sibling.x + sibling.width + gap - bounds.x, y: sibling.y - bounds.y
            ))
        case let .corner(corner, id):
            guard let bounds, let target = Self.corner(corner, for: bounds, in: id, of: document) else { return roots }
            return Self.shifted(roots, by: PenPoint(x: target.x - bounds.x, y: target.y - bounds.y))
        case .boardOffset:
            return zip(roots, copies.origins).map { root, origin in
                guard let offset = origin?.boardOffset else { return root }
                return Self.moved(root, to: offset)
            }
        }
    }

    /// Where the copies' top-left corner goes, in the container's coordinates — the
    /// canvas's when there is none — or `nil` when the container is not drawn.
    ///
    /// - Parameters:
    ///   - corner: What places the copies.
    ///   - bounds: The copies' bounds, as the clip lays them out.
    ///   - containerID: The free container, or `nil` for the canvas.
    ///   - document: The target document.
    private static func corner(
        _ corner: Corner,
        for bounds: PenRect,
        in containerID: String?,
        of document: EditableDocument
    ) -> PenPoint? {
        let layout = containerID.map { _ in Layout(of: document) }
        func local(_ point: PenPoint) -> PenPoint? {
            guard let containerID, let layout else { return point }
            return layout.local(point, in: containerID, of: document)
        }
        switch corner {
        case let .topLeft(point):
            return local(point)
        case let .center(point):
            return local(point).map { PenPoint(x: $0.x - bounds.width / 2, y: $0.y - bounds.height / 2) }
        case .innerTopLeft:
            guard let containerID, let layout else { return PenPoint(x: bounds.x, y: bounds.y) }
            guard let placement = layout.placement(of: containerID, in: document) else { return nil }
            let drawn = drawnNode(document.expandedID(of: .node(id: containerID)), in: layout.document)
            var padding = PenPadding.Edges.zero
            if case let .frame(data)? = drawn?.kind {
                padding = data.padding?.resolve() ?? .zero
            }
            return PenPoint(x: placement.box.x + padding.left, y: placement.box.y + padding.top)
        }
    }

    /// The roots in a free container, or, when their bounds would miss its box there,
    /// centered in it.
    ///
    /// When every root knows its offset in the parent it was copied out of, each takes
    /// that offset in the container — the same place in a new parent, and the original
    /// place in the parent it came from. Otherwise (a root copied from the canvas, a clip
    /// without origins) their canvas origins are carried into the container's
    /// coordinates.
    private func inContainer(
        _ roots: [PenNode],
        bounds: PenRect?,
        rects: [PenRect?],
        offsets: [PenPoint?],
        container id: String,
        in document: EditableDocument
    ) -> [PenNode] {
        guard let placement = Layout(of: document).placement(of: id, in: document),
              let inverse = placement.transform.inverted()
        else { return roots }
        let local: PenRect?
        let carried: [PenNode]
        let known = offsets.compactMap(\.self)
        if !roots.isEmpty, known.count == roots.count {
            carried = zip(roots, known).map(Self.moved(_:to:))
            local = PenClip.union(zip(zip(roots, known), rects).compactMap { pair, rect in
                guard let rect else { return nil }
                let (root, offset) = pair
                return PenRect(
                    x: rect.x + offset.x - Self.origin(of: root).x,
                    y: rect.y + offset.y - Self.origin(of: root).y,
                    width: rect.width, height: rect.height
                )
            })
        } else {
            carried = roots.map { Self.moved($0, to: inverse.apply(to: Self.origin(of: $0))) }
            local = bounds.map(inverse.bounds(of:))
        }
        guard let local else { return carried }
        let box = placement.box
        let misses = local.x >= box.x + box.width || local.x + local.width <= box.x
            || local.y >= box.y + box.height || local.y + local.height <= box.y
        guard misses else { return carried }
        return Self.shifted(carried, by: PenPoint(
            x: box.x + box.width / 2 - (local.x + local.width / 2),
            y: box.y + box.height / 2 - (local.y + local.height / 2)
        ))
    }

    /// A node's rect in its parent's coordinates — the canvas's for a root.
    private static func rect(of id: String, in document: EditableDocument) -> PenRect? {
        if document.parents[id] == nil {
            return RootOverlap.roots(in: document).first { $0.id == id }?.rect
        }
        return Layout(of: document).rects[document.expandedID(of: .node(id: id))]
    }

    /// A node of an expanded document, found by id.
    private static func drawnNode(_ id: String, in expanded: PenDocument) -> PenNode? {
        var pending = expanded.children
        while let node = pending.popLast() {
            if node.id == id { return node }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return nil
    }

    /// The point a root's `x` and `y` name; `0` for one it lacks.
    static func origin(of root: PenNode) -> PenPoint {
        PenPoint(x: root.common.x?.literalValue ?? 0, y: root.common.y?.literalValue ?? 0)
    }

    /// A root with its `x` and `y` set to a point.
    static func moved(_ root: PenNode, to point: PenPoint) -> PenNode {
        var moved = root
        moved.common.x = .literal(point.x)
        moved.common.y = .literal(point.y)
        return moved
    }

    /// Roots moved by an offset.
    static func shifted(_ roots: [PenNode], by offset: PenPoint) -> [PenNode] {
        roots.map { root in
            let origin = origin(of: root)
            return moved(root, to: PenPoint(x: origin.x + offset.x, y: origin.y + offset.y))
        }
    }
}
