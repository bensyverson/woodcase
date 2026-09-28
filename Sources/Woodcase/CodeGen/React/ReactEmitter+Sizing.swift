//
//  ReactEmitter+Sizing.swift
//  Woodcase
//

extension ReactEmitter {
    /// One side of a node's box.
    enum SizingAxis: Friendly {
        /// The horizontal side.
        case width
        /// The vertical side.
        case height
    }

    /// The CSS length for one side of a node, where CSS's own reading of `sizing` would
    /// miss Pen's size (`PenLayoutEngine.resolveIntrinsicSize(_:available:)`).
    ///
    /// - `fill_container(N)` with no container to fill — `placement` is ``ChildPlacement/free``
    ///   — is `N`; CSS's `100%` would resolve against a shrink-wrapped box and draw nothing.
    /// - `fit_content(N)` with nothing to fit is `N`; CSS's `fit-content` would collapse to 0.
    ///
    /// Anything else reads as ``emitSizing(_:)`` does.
    ///
    /// - Parameters:
    ///   - sizing: The side's declared sizing.
    ///   - placement: How the node's container places it.
    ///   - fitsContent: Whether the side has content to fit: a frame's flowed children or
    ///     padding, a text's glyphs. A shape has none.
    /// - Returns: A style value such as `150` or `"fit-content"`, or `nil` for none.
    static func emitSizing(_ sizing: PenSizing, placement: ChildPlacement, fitsContent: Bool) -> String? {
        switch sizing {
        case let .fillContainer(fallback?) where placement == .free: cssNumber(fallback)
        case let .fitContent(fallback?) where !fitsContent: cssNumber(fallback)
        default: emitSizing(sizing)
        }
    }

    /// The CSS length for one side of a frame, or `nil` to leave it to CSS.
    ///
    /// Beyond ``emitSizing(_:placement:fitsContent:)``'s fallbacks:
    ///
    /// - A `layout: "none"` frame never fits its children: Pen settles an unsized or
    ///   `fit_content` side at its fallback, 0 when there is none, and the children
    ///   overhang it (Ben's ruling, 2026-09-27).
    /// - A flowed frame with no declared size on its container's cross axis fits its
    ///   content, as Pen's `alignItems` has no stretch; CSS's default `align-items:
    ///   stretch` would stretch it, so the side is written as `fit-content`.
    ///
    /// - Parameters:
    ///   - declared: The side's declared sizing, `nil` when the frame sets none.
    ///   - axis: Which side.
    ///   - data: The frame.
    ///   - placement: How the frame's container places it.
    ///   - parentLayout: The container's layout, when it is a frame.
    ///   - isRoot: Whether the frame is the component's or page's root.
    static func emitFrameSizing(
        _ declared: PenSizing?,
        axis: SizingAxis,
        of data: PenNode.FrameData,
        placement: ChildPlacement,
        parentLayout: PenLayoutDirection?,
        isRoot: Bool
    ) -> String? {
        if data.layout == .some(.none) {
            switch declared {
            case nil: return cssNumber(0)
            case let .fitContent(fallback): return cssNumber(fallback ?? 0)
            case let declared?: return emitSizing(declared, placement: placement, fitsContent: true)
            }
        }
        guard let declared else {
            let crossAxis: SizingAxis = parentLayout == .vertical ? .width : .height
            return !isRoot && placement == .flow && axis == crossAxis ? "\"fit-content\"" : nil
        }
        return emitSizing(declared, placement: placement, fitsContent: frameFitsContent(data, along: axis))
    }

    /// Whether a flex frame has content to fit along `axis`: an enabled child in its flow,
    /// or padding on that side — the content `PenLayoutEngine` measures before it falls
    /// back. A padding that is still a variable counts as content.
    private static func frameFitsContent(_ data: PenNode.FrameData, along axis: SizingAxis) -> Bool {
        let flows = (data.children ?? []).contains {
            $0.common.enabled?.literalValue != false && $0.common.layoutPosition != .absolute
        }
        if flows { return true }
        guard let padding = data.padding else { return false }
        guard let edges = padding.resolve() else { return true }
        return (axis == .width ? edges.horizontal : edges.vertical) != 0
    }
}
