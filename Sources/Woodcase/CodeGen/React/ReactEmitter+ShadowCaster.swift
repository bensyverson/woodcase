//
//  ReactEmitter+ShadowCaster.swift
//  Woodcase
//

extension ReactEmitter {
    /// How the CSS of a node drawn as a box — a frame, a rectangle, an ellipse drawn as a
    /// box, a browser — casts the node's outer shadows.
    ///
    /// Pen casts an outer shadow from what the node paints, united with its children's
    /// silhouettes and clipped where the node clips (``PenShadowSilhouette``;
    /// <doc:PenRendering>, *Shadows*). Where that silhouette is the node's box, a
    /// `box-shadow` draws it exactly: CSS casts it from the border box at full strength
    /// whatever the background's alpha, keeps it outside that box, and spreads it by a
    /// stroke's reach. Anywhere else a `drop-shadow()` of the element's own rendering,
    /// children included, follows the silhouette Pen casts.
    enum ShadowCaster: String, Friendly {
        /// A `box-shadow` of the border box, grown by the stroke's reach
        /// (``ReactEmitter/shadowSpread(_:)``): a node whose fill paints its box and
        /// nothing of whose content reaches past it (``ReactEmitter/contentStaysInBox(_:)``),
        /// and a frame whose children may reach past a translucent fill, where it loses only
        /// those children's shadows.
        case box
        /// `drop-shadow()` filters of what the element paints, its stroke, overlays and
        /// children included (``ReactEmitter/NodeEffects/dropShadowFunctions``): a node
        /// whose fill paints nothing, and a frame whose children may reach past an opaque
        /// fill.
        ///
        /// A drop-shadow is cast at the painted alpha, where Pen's silhouette is opaque: a
        /// translucent part casts a fainter shadow that shows through it, a child's own
        /// shadow is cast again, and an inner shadow on a fill-less box casts too.
        case content
    }

    /// How the node's outer shadows are cast (``ShadowCaster``).
    ///
    /// - Parameter node: A frame, rectangle, ellipse or browser node; any other kind is
    ///   ``ShadowCaster/box``, which those never use.
    /// - Returns: ``ShadowCaster/content`` when the node's fill paints nothing (``paintsBox(_:)``),
    ///   or for a frame whose children may reach past an opaque fill (``contentStaysInBox(_:)``,
    ///   ``paintsOpaquely(_:)``);
    ///   ``ShadowCaster/box`` otherwise.
    static func shadowCaster(_ node: PenNode) -> ShadowCaster {
        switch node.kind {
        case let .frame(data):
            guard paintsBox(data.fills) else { return .content }
            // Children may reach past the box: a drop-shadow casts them, and is exact for the
            // box only where the fill hides what is behind it. Under a translucent fill the
            // box-shadow, exact for the box, loses less than the faint, see-through drop-shadow.
            return contentStaysInBox(data) || !paintsOpaquely(data.fills) ? .box : .content
        case let .rectangle(data):
            return paintsBox(data.fills) ? .box : .content
        case let .ellipse(data):
            return paintsBox(data.fills) ? .box : .content
        default:
            return .box
        }
    }

    /// Whether `fills` paint the node's box: one enabled fill that paints
    /// (``PenFills/hasVisiblePaint``), a document variable's color counting as painting,
    /// since its value is the theme's and the page's to choose.
    static func paintsBox(_ fills: PenFills?) -> Bool {
        (fills?.all ?? []).contains { fill in
            guard fill.isEnabled else { return false }
            if fill.solidColor?.variableName != nil {
                return true
            }
            return PenFills.single(fill).hasVisiblePaint
        }
    }

    /// Whether one of `fills` hides what lies behind the box: an enabled color at full
    /// alpha, a document variable's color counting as one. A gradient, an image or a mesh
    /// may have transparent parts, so none counts.
    static func paintsOpaquely(_ fills: PenFills?) -> Bool {
        (fills?.all ?? []).contains { fill in
            guard fill.isEnabled, let color = fill.solidColor else { return false }
            switch color {
            case .variable: return true
            case let .literal(hex): return (PenColorParser.parse(hex)?.alpha ?? 0) >= 1
            }
        }
    }
}
