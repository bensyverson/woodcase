//
//  ReactEmitter+ShadowContainment.swift
//  Woodcase
//

extension ReactEmitter {
    /// Whether everything a frame's children paint provably stays inside the frame's box,
    /// so a `box-shadow` of the box casts all of it (``shadowCaster(_:)``).
    ///
    /// The emitter has no layout to measure, so this reads the document: a clipping frame
    /// holds everything; a child in a flex flow is taken to stay inside, as a flow places
    /// it there; a child placed freely, at its own `x` and `y`, stays inside when its
    /// literal box, grown by any painted stroke reaching past it, fits the frame's literal
    /// size and it is not turned. A child frame's content must stay inside it in turn, and a
    /// group's children, placed about its anchor, are never taken to. Anything this cannot
    /// prove — a variable, a fit or fill size — counts as reaching past the box.
    ///
    /// - Parameter data: The frame.
    /// - Returns: Whether the frame's content stays inside its box.
    static func contentStaysInBox(_ data: PenNode.FrameData) -> Bool {
        if data.clip?.literalValue == true {
            return true
        }
        let placesFreely = data.layout == .some(.none)
        let box = (width: data.width?.fixedValue, height: data.height?.fixedValue)
        return (data.children ?? []).allSatisfy { child in
            guard child.common.enabled?.literalValue != false else { return true }
            if placesFreely || child.common.layoutPosition == .absolute {
                guard let width = box.width, let height = box.height,
                      fits(child, inWidth: width, height: height)
                else { return false }
            }
            return ownContentStaysInBox(child)
        }
    }

    /// Whether the child's literal box, grown by its painted stroke's reach, sits inside a
    /// `width` × `height` box at the origin, unturned.
    private static func fits(_ child: PenNode, inWidth width: Double, height: Double) -> Bool {
        let common = child.common
        guard (common.rotation?.literalValue ?? 0) == 0,
              let x = literal(common.x), let y = literal(common.y),
              let childWidth = PenLayoutEngine.widthSizing(of: child).fixedValue,
              let childHeight = PenLayoutEngine.heightSizing(of: child).fixedValue,
              let reach = strokeReach(of: child)
        else { return false }
        return x - reach.left >= 0 && y - reach.top >= 0
            && x + childWidth + reach.right <= width && y + childHeight + reach.bottom <= height
    }

    /// A position's literal value, `0` when it is absent, or `nil` for a variable.
    private static func literal(_ value: PenValue<Double>?) -> Double? {
        guard let value else { return 0 }
        return value.literalValue
    }

    /// How far the node's painted stroke reaches past its box on each side, or `nil` when
    /// a width is a variable.
    private static func strokeReach(of node: PenNode) -> (top: Double, right: Double, bottom: Double, left: Double)? {
        guard let stroke = PenLayoutEngine.strokable(node)?.drawn(on: node), PaintRoute(stroke.stroke) != .none else {
            return (0, 0, 0, 0)
        }
        let outsets = StrokeRing(stroke).outsets
        guard let top = outsets.top.literalPoints, let right = outsets.right.literalPoints,
              let bottom = outsets.bottom.literalPoints, let left = outsets.left.literalPoints
        else { return nil }
        return (top, right, bottom, left)
    }

    /// Whether what the node's descendants paint stays inside the node: a frame's as
    /// ``contentStaysInBox(_:)`` decides, a group's never, and any other kind's always.
    private static func ownContentStaysInBox(_ node: PenNode) -> Bool {
        switch node.kind {
        case let .frame(data): contentStaysInBox(data)
        case .group: false
        default: true
        }
    }
}
