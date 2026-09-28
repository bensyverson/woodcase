//
//  ReactEmitter+InnerShadowRoute.swift
//  Woodcase
//

extension ReactEmitter {
    /// How React writes a node's inner shadows, which decides what it warns about them.
    enum InnerShadowRoute: Friendly {
        /// `inset` entries of the box's `box-shadow` (``emitStrokeAndEffects(stroke:effects:showsBackdrop:layered:)``):
        /// drawn, but without a blend mode, since CSS blends an element and not one shadow.
        case insetBoxShadow
        /// An SVG filter over the node's silhouette (``svgInnerShadowFilter(_:id:region:scale:composite:)``),
        /// which draws each shadow with its blend mode.
        case svgFilter
        /// Left out, with this generate-time warning.
        case dropped(warning: String)
        /// Not drawn and not warned about: Pen draws none either — a line has no inside.
        case none
    }

    /// The route of `node`'s inner shadows.
    static func innerShadowRoute(_ node: PenNode) -> InnerShadowRoute {
        switch node.kind {
        case .rectangle, .frame, .browser:
            .insetBoxShadow
        case let .ellipse(data):
            drawsAsBox(data) ? .insetBoxShadow : .svgFilter
        case .polygon, .path, .icon:
            .svgFilter
        case .text:
            .dropped(warning: textInnerShadowWarning)
        case .group:
            .dropped(warning: groupInnerShadowWarning)
        default:
            .none
        }
    }

    /// Whether an ellipse is written as a CSS box with `border-radius: 50%` — no inner
    /// radius and a full sweep — rather than as an SVG path
    /// (``emitEllipse(_:data:indent:ctx:isRoot:parentLayout:)``).
    static func drawsAsBox(_ data: PenNode.EllipseData) -> Bool {
        (data.innerRadius?.literalValue ?? 0) <= 0 && abs(data.sweepAngle?.literalValue ?? 360) >= 360
    }
}
