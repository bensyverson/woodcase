//
//  EditPlanner+Restructure.swift
//  Woodcase
//

import Foundation

/// What Group, Frame Selection, Ungroup and a move share: finding the stored nodes they act
/// on, and rewriting a node's placement so it is drawn where it was after it changes parent.
///
/// A node placed by its own `x`/`y` is drawn by `translate(x, y) · turn · flip` about its
/// anchor, in its parent's own coordinates (``PenLayoutEngine/placement(of:rect:layoutRects:)``).
/// So a node that moves to a new parent keeps its canvas quad when its new local map is
/// the new parent's canvas map inverted, after its old canvas map — read back as an
/// anchor, a turn and two flips. Pen has no scale, so every map is a turn, flips and a
/// move, and that reading always exists.
extension EditPlanner {
    /// An affine map of the plane.
    typealias Transform = PenLayoutEngine.PlaneTransform

    /// The stored id a group or ungroup acts on, from a stored id or an expanded one.
    ///
    /// An editor holds expanded ids, so an instance root's `<ref>/<component root>`
    /// resolves to its `ref` node; a node inside an instance, or inside a slot's
    /// content, is refused, because an instance's nodes are its component's.
    ///
    /// - Parameters:
    ///   - id: A stored or expanded id.
    ///   - document: The document.
    /// - Returns: The stored id.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/addressNotFound`` or
    ///   ``EditRefusal/Code/insideInstance``.
    static func restructuredID(_ id: String, in document: EditableDocument) throws(EditRefusal) -> String {
        let stored: String
        if document.node(id: id) != nil {
            stored = id
        } else {
            switch document.resolve(expandedID: id) {
            case let .node(found)?:
                stored = found
            case .instanceDescendant?:
                throw insideInstanceRefusal(id)
            case nil:
                throw EditRefusal(code: .addressNotFound, address: id, message: "No node has the id \(id).")
            }
        }
        let insideRef = document.ancestors(of: stored).contains { ancestor in
            if case .ref = document.node(id: ancestor)?.kind { return true }
            return false
        }
        if insideRef { throw insideInstanceRefusal(id) }
        return stored
    }

    /// The refusal for a node inside an instance.
    private static func insideInstanceRefusal(_ id: String) -> EditRefusal {
        EditRefusal(
            code: .insideInstance,
            address: id,
            message: "\(id) is inside a component instance, whose nodes are its component's; "
                + "edit the component itself, or detach the instance."
        )
    }

    /// Where a node sits in document order: its index among its siblings at every level,
    /// root first. A later path is drawn on top of an earlier one.
    ///
    /// - Parameters:
    ///   - id: A stored node.
    ///   - document: The document.
    /// - Returns: The indices, outermost first.
    static func orderPath(of id: String, in document: EditableDocument) -> [Int] {
        var path: [Int] = []
        var cursor: String? = id
        while let current = cursor {
            let parent = document.parentID(of: current)
            let siblings = parent.map { document.childIDs(of: $0) } ?? document.rootOrder
            path.insert(siblings.firstIndex(of: current) ?? 0, at: 0)
            cursor = parent
        }
        return path
    }

    /// The index of a node among its parent's children, or among the roots.
    static func siblingIndex(of id: String, in document: EditableDocument) -> Int {
        let siblings = document.parentID(of: id).map { document.childIDs(of: $0) } ?? document.rootOrder
        return siblings.firstIndex(of: id) ?? siblings.count
    }

    /// Whether a stored node lays out its children: a frame whose layout is not `none`.
    static func laysOut(_ id: String?, in document: EditableDocument) -> Bool {
        guard let id, case let .frame(data)? = document.node(id: id)?.kind else { return false }
        return (data.layout ?? .horizontal) != .none
    }

    /// The map from a stored node's own coordinates to the canvas, read from the layout;
    /// the identity for the canvas itself (`nil`).
    ///
    /// - Returns: The map, or `nil` when the layout placed no such node: a hidden child of
    ///   a stack, which has no place of its own, or a layout older than the document.
    static func canvasMap(of id: String?, in document: EditableDocument, layout: PenLayoutState) -> Transform? {
        guard let id else { return .identity }
        let expanded = document.expandedID(of: .node(id: id))
        return PenLayoutEngine.canvasPlacement(of: expanded, in: layout.document, layoutRects: layout.rects)?.transform
    }

    /// The quad a stored node is drawn as on the canvas, or `nil` when it is not drawn.
    static func canvasCorners(of id: String, in document: EditableDocument, layout: PenLayoutState) -> [PenPoint]? {
        let expanded = document.expandedID(of: .node(id: id))
        return PenLayoutEngine.canvasPlacement(of: expanded, in: layout.document, layoutRects: layout.rects)?.corners
    }

    /// Whether a node and its ancestors flip, taken together: each flip an odd number of
    /// times along the chain.
    static func flipParity(of id: String?, in document: EditableDocument) -> (x: Bool, y: Bool) {
        var parity = (x: false, y: false)
        var cursor = id
        while let current = cursor, let node = document.node(id: current) {
            if node.common.flipX?.literalValue == true { parity.x.toggle() }
            if node.common.flipY?.literalValue == true { parity.y.toggle() }
            cursor = document.parentID(of: current)
        }
        return parity
    }

    // MARK: - Re-placing a node

    /// How a node is to be placed in its new parent.
    enum Placing {
        /// By its own `x`/`y`, in a parent that does not lay out its children.
        case free
        /// By its own `x`/`y`, out of the flow of a parent that lays out the rest.
        case absolute
        /// By the flow of a parent that lays out its children.
        case inFlow
    }

    /// The writes that keep a node drawn where it was after it moves to a new parent.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - oldParent: Its parent as it stands, or `nil` for the canvas.
    ///   - newParentMap: The canvas map of its new parent's own coordinates.
    ///   - newParentFlips: The flip parity of its new parent's chain.
    ///   - placing: How the new parent places it.
    ///   - offset: How far it is carried on the canvas as it moves; `.zero` keeps it
    ///     exactly where it is drawn.
    ///   - snapping: How the new `x`/`y` are rounded before they are compared with the
    ///     stored ones.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of the document as it stands.
    /// - Returns: The property writes: empty when nothing changes, and when the layout
    ///   placed no such node — a hidden child of a stack keeps what it stored.
    static func placementWrites(
        of id: String,
        from oldParent: String?,
        newParentMap: Transform,
        newParentFlips: (x: Bool, y: Bool),
        placing: Placing,
        movedBy offset: PenPoint = .zero,
        snapping: PlacementSnapping = .none,
        in document: EditableDocument,
        layout: PenLayoutState
    ) -> [String: AnyCodable] {
        guard let node = document.node(id: id),
              let drawn = canvasMap(of: id, in: document, layout: layout),
              let oldParentMap = canvasMap(of: oldParent, in: document, layout: layout)
        else { return [:] }
        let subject = PlacementSubject(
            node: node,
            drawn: drawn,
            drawnSize: layout.rects[document.expandedID(of: .node(id: id))]?.drawnSize,
            oldParentMap: oldParentMap,
            oldParentFlips: flipParity(of: oldParent, in: document)
        )
        return placementWrites(
            of: subject, newParentMap: newParentMap, newParentFlips: newParentFlips,
            placing: placing, movedBy: offset, snapping: snapping
        )
    }

    /// A node about to be re-placed, as the layout drew it: what
    /// ``placementWrites(of:newParentMap:newParentFlips:placing:movedBy:snapping:)`` reads.
    ///
    /// A stored node reads it from the store and the layout; a node in a slot's content,
    /// which has no storage of its own, from its fill and the layout's expanded ids.
    struct PlacementSubject {
        /// The node, its own properties as drawn.
        var node: PenNode

        /// The map from the node's own coordinates to the canvas.
        var drawn: Transform

        /// The size the layout drew it at, or `nil` when it drew none.
        var drawnSize: PenSize?

        /// The canvas map of its parent's own coordinates.
        var oldParentMap: Transform

        /// The flip parity of its parent's chain.
        var oldParentFlips: (x: Bool, y: Bool)
    }

    /// The writes that keep a node drawn where it was after it moves to a new parent.
    ///
    /// - Parameters:
    ///   - subject: The node, as it was drawn.
    ///   - newParentMap: The canvas map of its new parent's own coordinates.
    ///   - newParentFlips: The flip parity of its new parent's chain.
    ///   - placing: How the new parent places it.
    ///   - offset: How far it is carried on the canvas as it moves.
    ///   - snapping: How the new `x`/`y` are rounded before they are compared with the
    ///     stored ones.
    /// - Returns: The property writes, by property path; empty when nothing changes.
    static func placementWrites(
        of subject: PlacementSubject,
        newParentMap: Transform,
        newParentFlips: (x: Bool, y: Bool),
        placing: Placing,
        movedBy offset: PenPoint = .zero,
        snapping: PlacementSnapping = .none
    ) -> [String: AnyCodable] {
        guard let inverse = newParentMap.inverted() else { return [:] }
        let node = subject.node
        let drawn = subject.drawn
        let oldParentMap = subject.oldParentMap
        var writes: [String: AnyCodable] = [:]
        let common = NodePropertyCodec.commonPrefix
        let canvas = Transform.translation(x: offset.x, y: offset.y).concatenating(drawn)
        let local = inverse.concatenating(canvas)

        // The turn and flips change only when the new parent is turned or flipped
        // differently from the old one.
        let change = inverse.concatenating(oldParentMap)
        if !isTranslation(change) {
            let oldFlips = subject.oldParentFlips
            var flipX = (node.common.flipX?.literalValue == true) != (oldFlips.x != newParentFlips.x)
            let flipY = (node.common.flipY?.literalValue == true) != (oldFlips.y != newParentFlips.y)
            // A flip bound to a variable is not in the parity; the map's handedness is the
            // truth, so a mirror the parity missed goes on the left-to-right flip.
            if (local.a * local.d - local.b * local.c < 0) != (flipX != flipY) {
                flipX.toggle()
            }
            let rotation = rotation(of: local, flipX: flipX)
            let stored = node.common.rotation
            let boundToVariable = stored != nil && stored?.literalValue == nil
            if boundToVariable || !sameAngle(rotation, stored?.literalValue ?? 0) {
                writes[common + "rotation"] = sameAngle(rotation, 0) ? .null : number(rotation)
            }
            if flipX != (node.common.flipX?.literalValue == true) {
                writes[common + "flipX"] = flipX ? .bool(true) : .null
            }
            if flipY != (node.common.flipY?.literalValue == true) {
                writes[common + "flipY"] = flipY ? .bool(true) : .null
            }
        }

        switch placing {
        case .free, .absolute:
            for (field, raw) in [("x", local.tx), ("y", local.ty)] {
                let value = snapping.snapped(raw)
                let stored = field == "x" ? node.common.x : node.common.y
                if stored?.literalValue.map({ abs($0 - value) > tolerance }) ?? true {
                    writes[common + field] = number(value)
                }
            }
        case .inFlow:
            if node.common.x != nil { writes[common + "x"] = .null }
            if node.common.y != nil { writes[common + "y"] = .null }
        }
        let position: PenLayoutPosition? = placing == .absolute ? .absolute : nil
        if node.common.layoutPosition != position {
            writes[common + "layoutPosition"] = position.map { .string($0.rawValue) } ?? .null
        }

        let kept = keptSizeWrites(of: node, drawnSize: subject.drawnSize, laidOut: placing == .inFlow)
        writes.merge(kept) { _, kept in kept }
        return writes
    }

    // MARK: - Numbers

    /// How close two coordinates are to count as the same.
    static let tolerance = 1e-9

    /// A number as it is written: snapped to a millionth when it is within floating-point
    /// noise of one, and an integer when it is whole.
    static func number(_ value: Double) -> AnyCodable {
        let snapped = (value * 1e6).rounded() / 1e6
        let tidy = abs(value - snapped) < 1e-7 ? snapped : value
        let clean = tidy == 0 ? 0 : tidy
        return PenPropertyDefault.number(clean).value ?? .double(clean)
    }

    /// Whether a map only moves the plane.
    private static func isTranslation(_ map: Transform) -> Bool {
        abs(map.a - 1) < tolerance && abs(map.b) < tolerance && abs(map.c) < tolerance && abs(map.d - 1) < tolerance
    }

    /// Pen's counter-clockwise degrees of a map's turn, once its flips are taken off it,
    /// in (−180, 180].
    ///
    /// The map's linear part is turn · flip, and a flip top to bottom touches only its
    /// second column, so the first column with the left-to-right flip undone is the
    /// turn's.
    private static func rotation(of map: Transform, flipX: Bool) -> Double {
        let a = map.a * (flipX ? -1 : 1)
        let b = map.b * (flipX ? -1 : 1)
        let radians = atan2(b, a)
        var degrees = -radians * 180 / .pi
        if degrees <= -180 { degrees += 360 }
        if degrees > 180 { degrees -= 360 }
        return degrees
    }

    /// Whether two angles in degrees are the same turn.
    private static func sameAngle(_ lhs: Double, _ rhs: Double) -> Bool {
        let difference = (lhs - rhs).truncatingRemainder(dividingBy: 360)
        return abs(difference) < 1e-6 || abs(abs(difference) - 360) < 1e-6
    }
}
