//
//  PasteSite.swift
//  Woodcase
//

import Foundation

/// Where a paste's copied roots go in the target, and how they are positioned there —
/// a ``PasteTarget`` resolved against the document.
struct PasteSite: Friendly {
    /// How the copies are positioned.
    enum Arrangement: Friendly {
        /// As they were copied: canvas coordinates, unchanged.
        case asCopied

        /// Centered on a canvas point.
        case centered(on: PenPoint)

        /// In a stack's flow: no coordinates.
        case flow

        /// In a free container, at their canvas position in its coordinates — or
        /// centered in it when that misses it.
        case container(id: String)

        /// To the right of a node, top-aligned with it, a gap away.
        case beside(id: String, gap: Double)
    }

    /// The parent the copies are inserted into, or `nil` for the canvas.
    var parentID: String?

    /// The index of the first copy among the parent's children (or the roots), or `nil`
    /// to append.
    var index: Int?

    /// How the copies are positioned.
    var arrangement: Arrangement

    /// Resolves a paste target.
    ///
    /// - Parameters:
    ///   - target: Where the paste was asked to go.
    ///   - document: The target document.
    /// - Throws: ``PasteError/targetNotFound(id:)`` for an id the document does not
    ///   store, ``PasteError/notAContainer(id:)`` for a container that cannot hold
    ///   children.
    init(_ target: PasteTarget, in document: EditableDocument) throws {
        switch target {
        case .inPlace:
            self.init(parentID: nil, index: nil, arrangement: .asCopied)
        case let .canvas(center):
            self.init(parentID: nil, index: nil, arrangement: .centered(on: center))
        case let .inside(id):
            guard let container = document.nodes[id] else { throw PasteError.targetNotFound(id: id) }
            switch container.kind {
            case .frame:
                self.init(parentID: id, index: nil, arrangement: Self.isStack(container) ? .flow : .container(id: id))
            case .group:
                self.init(parentID: id, index: nil, arrangement: .container(id: id))
            default:
                throw PasteError.notAContainer(id: id)
            }
        case let .after(id):
            guard document.nodes[id] != nil else { throw PasteError.targetNotFound(id: id) }
            guard let parentID = document.parents[id] else {
                let index = (document.rootOrder.firstIndex(of: id) ?? document.rootOrder.count - 1) + 1
                self.init(parentID: nil, index: index, arrangement: .beside(id: id, gap: RootOverlap.margin))
                return
            }
            let index = ((document.children[parentID] ?? []).firstIndex(of: id) ?? 0) + 1
            let inFlow = document.nodes[parentID].map(Self.isStack) ?? false
            self.init(
                parentID: parentID, index: index,
                arrangement: inFlow ? .flow : .beside(id: id, gap: PenClip.besideGap)
            )
        }
    }

    /// Creates a site from its parts.
    init(parentID: String?, index: Int?, arrangement: Arrangement) {
        self.parentID = parentID
        self.index = index
        self.arrangement = arrangement
    }

    /// Whether a node lays its children out itself: a frame whose layout is not `none`
    /// (a frame that says nothing is horizontal).
    static func isStack(_ node: PenNode) -> Bool {
        guard case let .frame(data) = node.kind else { return false }
        return (data.layout ?? .horizontal) != .none
    }

    // MARK: - Positioning

    /// The copied roots, positioned for this site.
    ///
    /// - Parameters:
    ///   - roots: The copied roots, carrying the canvas coordinates they were copied at.
    ///   - rects: Each root's rect on the canvas, as the clip lays them out, in the same
    ///     order.
    ///   - offsets: Each root's offset in the parent it was copied out of
    ///     (``PenClip/offsets``), in the same order; `nil` for a root that has none.
    ///   - document: The target document.
    /// - Returns: The roots, positioned.
    func positioned(
        _ roots: [PenNode],
        rects: [PenRect?],
        offsets: [PenPoint?],
        in document: EditableDocument
    ) -> [PenNode] {
        let bounds = PenClip.union(rects.compactMap(\.self))
        switch arrangement {
        case .asCopied:
            return roots
        case .flow:
            return roots.map { root in
                var placed = root
                placed.common.x = nil
                placed.common.y = nil
                return placed
            }
        case let .centered(center):
            guard let bounds else { return roots }
            return Self.shifted(roots, by: PenPoint(
                x: center.x - (bounds.x + bounds.width / 2), y: center.y - (bounds.y + bounds.height / 2)
            ))
        case let .container(id):
            return inContainer(roots, bounds: bounds, rects: rects, offsets: offsets, container: id, in: document)
        case let .beside(id, gap):
            guard let bounds, let sibling = Self.rect(of: id, in: document) else { return roots }
            return Self.shifted(roots, by: PenPoint(
                x: sibling.x + sibling.width + gap - bounds.x, y: sibling.y - bounds.y
            ))
        }
    }

    /// The roots in a free container, or, when their bounds would miss its box there,
    /// centered in it.
    ///
    /// When every root knows its offset in the parent it was copied out of, each takes
    /// that offset in the container — the same place in a new parent, and the original
    /// place in the parent it came from. Otherwise (a root copied from the canvas, a clip
    /// written before offsets) their canvas origins are carried into the container's
    /// coordinates.
    private func inContainer(
        _ roots: [PenNode],
        bounds: PenRect?,
        rects: [PenRect?],
        offsets: [PenPoint?],
        container id: String,
        in document: EditableDocument
    ) -> [PenNode] {
        let (expanded, layoutRects) = Self.layout(of: document)
        guard let placement = PenLayoutEngine.canvasPlacement(
            of: document.expandedID(of: .node(id: id)), in: expanded, layoutRects: layoutRects
        ), let inverse = placement.transform.inverted()
        else { return roots }
        let local: PenRect?
        let carried: [PenNode]
        let known = offsets.compactMap(\.self)
        if !roots.isEmpty, known.count == roots.count {
            carried = zip(roots, known).map { root, offset in
                var placed = root
                placed.common.x = .literal(offset.x)
                placed.common.y = .literal(offset.y)
                return placed
            }
            local = PenClip.union(zip(zip(roots, known), rects).compactMap { pair, rect in
                guard let rect else { return nil }
                let (root, offset) = pair
                return PenRect(
                    x: rect.x + offset.x - (root.common.x?.literalValue ?? 0),
                    y: rect.y + offset.y - (root.common.y?.literalValue ?? 0),
                    width: rect.width, height: rect.height
                )
            })
        } else {
            carried = roots.map { root in
                var placed = root
                let origin = inverse.apply(to: PenPoint(x: root.common.x?.literalValue ?? 0, y: root.common.y?.literalValue ?? 0))
                placed.common.x = .literal(origin.x)
                placed.common.y = .literal(origin.y)
                return placed
            }
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
        return layout(of: document).rects[document.expandedID(of: .node(id: id))]
    }

    /// The document laid out as the canvas draws it.
    private static func layout(of document: EditableDocument) -> (document: PenDocument, rects: [String: PenRect]) {
        let expanded = PenVariableResolver.resolve(document.expanded(for: .canvas))
        return (expanded, PenLayoutEngine.layout(expanded))
    }

    /// Roots moved by an offset.
    static func shifted(_ roots: [PenNode], by offset: PenPoint) -> [PenNode] {
        roots.map { root in
            var moved = root
            moved.common.x = .literal((root.common.x?.literalValue ?? 0) + offset.x)
            moved.common.y = .literal((root.common.y?.literalValue ?? 0) + offset.y)
            return moved
        }
    }
}
