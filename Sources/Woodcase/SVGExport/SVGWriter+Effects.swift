//
//  SVGWriter+Effects.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A node's enabled effects, sorted the way the CG renderer reads them.
    struct Effects: Friendly {
        /// The outer shadows, in array order.
        let outerShadows: [PenEffect.PenShadowEffect]
        /// The inner shadows, in array order.
        let innerShadows: [PenEffect.PenShadowEffect]
        /// The first layer blur's radius, when it blurs at all.
        let blur: Double?

        /// Sorts `effects`; a disabled effect is dropped. A background blur is dropped too:
        /// SVG cannot read what is behind an element (see <doc:PenSVGExport>).
        init(_ effects: PenEffects?) {
            let all = (effects?.all ?? []).filter(\.isEnabled)
            outerShadows = all.compactMap { effect in
                guard case let .shadow(shadow) = effect, shadow.shadowType != .inner else { return nil }
                return shadow
            }
            innerShadows = all.compactMap { effect in
                guard case let .shadow(shadow) = effect, shadow.shadowType == .inner else { return nil }
                return shadow
            }
            blur = all.lazy.compactMap { effect -> Double? in
                guard case let .blur(blur) = effect, let radius = blur.radius?.literalValue, radius > 0 else { return nil }
                return radius
            }.first
        }
    }

    /// Each outer shadow cast by `silhouette`, as Pen casts it: blurred, moved, in its color,
    /// and knocked out where the silhouette is, so a translucent fill never shows its own
    /// shadow through it.
    ///
    /// - Parameters:
    ///   - shadows: The outer shadows, in order.
    ///   - silhouette: What casts them, drawn opaque.
    ///   - region: The silhouette's bounds, in the node's coordinates.
    ///   - canvas: The map from the node's coordinates to the canvas.
    /// - Returns: One element per shadow: the silhouette, filtered to its shadow alone.
    func outerShadows(
        _ shadows: [PenEffect.PenShadowEffect],
        silhouette: SVGElement,
        region: CGRect,
        canvas: PenLayoutEngine.PlaneTransform
    ) -> [SVGElement] {
        shadows.map { shadow in
            let cast = Cast(shadow, canvas: canvas)
            let filter = SVGElement("filter", cast.region(around: region), children: [
                SVGElement("feGaussianBlur", ["in": "SourceAlpha", "stdDeviation": cast.deviation.svgNumber]),
                SVGElement("feOffset", ["dx": cast.dx.svgNumber, "dy": cast.dy.svgNumber, "result": "cast"]),
                SVGElement("feFlood", ["flood-color": cast.color.svgColor, "flood-opacity": cast.color.svgAlpha]),
                SVGElement("feComposite", ["in2": "cast", "operator": "in", "result": "shadow"]),
                SVGElement("feComposite", ["in": "shadow", "in2": "SourceAlpha", "operator": "out"]),
            ])
            var element = silhouette
            element["filter"] = define(filter, prefix: "shadow")
            element["style"] = shadow.blendMode?.svgStyle
            return element
        }
    }

    /// Each inner shadow inside `silhouette`: the inverse of the silhouette, blurred,
    /// moved and colored, kept only where the silhouette is.
    ///
    /// - Parameters:
    ///   - shadows: The inner shadows, in order.
    ///   - silhouette: The shape they fall inside, drawn opaque.
    ///   - region: The silhouette's bounds, in the node's coordinates.
    ///   - canvas: The map from the node's coordinates to the canvas.
    /// - Returns: One element per shadow.
    func innerShadows(
        _ shadows: [PenEffect.PenShadowEffect],
        silhouette: SVGElement,
        region: CGRect,
        canvas: PenLayoutEngine.PlaneTransform
    ) -> [SVGElement] {
        shadows.map { shadow in
            let cast = Cast(shadow, canvas: canvas)
            let filter = SVGElement("filter", cast.region(around: region), children: [
                // Ink everywhere the silhouette is not. An `feComponentTransfer` table over
                // `SourceAlpha` says the same, and WebKit draws nothing for it.
                SVGElement("feFlood", ["flood-color": "#000000", "flood-opacity": "1", "result": "ink"]),
                SVGElement("feComposite", ["in": "ink", "in2": "SourceAlpha", "operator": "out", "result": "inverse"]),
                SVGElement("feGaussianBlur", ["in": "inverse", "stdDeviation": cast.deviation.svgNumber]),
                SVGElement("feOffset", ["dx": cast.dx.svgNumber, "dy": cast.dy.svgNumber, "result": "cast"]),
                SVGElement("feFlood", ["flood-color": cast.color.svgColor, "flood-opacity": cast.color.svgAlpha]),
                SVGElement("feComposite", ["in2": "cast", "operator": "in"]),
                SVGElement("feComposite", ["in2": "SourceAlpha", "operator": "in"]),
            ])
            var element = silhouette
            element["filter"] = define(filter, prefix: "shadow")
            element["style"] = shadow.blendMode?.svgStyle
            return element
        }
    }

    /// A group's inner shadows, cast inside its children's combined silhouette and drawn
    /// over them.
    func groupInnerShadows(
        _ shadows: [PenEffect.PenShadowEffect],
        box: PenRect,
        canvas: PenLayoutEngine.PlaneTransform,
        of children: [PenNode]
    ) -> [SVGElement] {
        guard !shadows.isEmpty, !children.isEmpty else { return [] }
        return innerShadows(shadows, silhouette: groupSilhouette(of: children), region: box.cgRect, canvas: canvas)
    }

    /// A layer blur's filter: a Gaussian of sigma `radius / 2` points, as Pen blurs.
    ///
    /// - Parameters:
    ///   - radius: The blur's radius.
    ///   - region: Everything the node paints, in its own coordinates.
    /// - Returns: `url(#…)` for the filter.
    func blurFilter(radius: Double, region: CGRect) -> String {
        let deviation = radius / 2
        let reach = 3 * deviation + 2
        let area = region.insetBy(dx: -reach, dy: -reach)
        let filter = SVGElement("filter", Cast.filterRegion(area), children: [
            SVGElement("feGaussianBlur", ["stdDeviation": deviation.svgNumber]),
        ])
        return define(filter, prefix: "blur")
    }

    /// One shadow's geometry in a node's own coordinates.
    private struct Cast {
        /// The Gaussian's sigma: half the shadow's blur, as CG's shadow blur means.
        let deviation: Double
        /// The offset along the node's own x axis.
        let dx: Double
        /// The offset along the node's own y axis.
        let dy: Double
        /// The shadow's color, black at half alpha when it names none.
        let color: PenHexColor

        /// Reads `shadow` for a node whose own coordinates map to the canvas by `canvas`.
        ///
        /// CG casts a shadow's offset in device space, untouched by the node's turn or flip,
        /// so a turned card's shadow still falls down and right on the screen. An SVG
        /// filter works in the element's own coordinates; the screen offset is carried back
        /// through the inverse of the node's linear map to land in the same place.
        init(_ shadow: PenEffect.PenShadowEffect, canvas: PenLayoutEngine.PlaneTransform) {
            deviation = max(0, shadow.blur?.literalValue ?? 0) / 2
            let x = shadow.offset?.x.literalValue ?? 0
            let y = shadow.offset?.y.literalValue ?? 0
            let linear = PenLayoutEngine.PlaneTransform(a: canvas.a, b: canvas.b, c: canvas.c, d: canvas.d)
            let local = linear.inverted()?.apply(to: PenPoint(x: x, y: y)) ?? PenPoint(x: x, y: y)
            dx = local.x
            dy = local.y
            color = shadow.color?.literalValue.flatMap(PenHexColor.init) ?? PenHexColor(red: 0, green: 0, blue: 0, alpha: 128)
        }

        /// The filter region around `bounds` that holds the whole shadow.
        func region(around bounds: CGRect) -> KeyValuePairs<String, String?> {
            let reach = 3 * deviation + abs(dx) + abs(dy) + 2
            return Self.filterRegion(bounds.insetBy(dx: -reach, dy: -reach))
        }

        /// A filter's attributes covering `area`, in the element's own coordinates.
        static func filterRegion(_ area: CGRect) -> KeyValuePairs<String, String?> {
            [
                "filterUnits": "userSpaceOnUse",
                "x": Double(area.minX).svgNumber, "y": Double(area.minY).svgNumber,
                "width": Double(area.width).svgNumber, "height": Double(area.height).svgNumber,
                "color-interpolation-filters": "sRGB",
            ]
        }
    }
}

private extension PenEffect {
    /// Whether the effect draws: an explicit `enabled: false` turns it off.
    var isEnabled: Bool {
        switch self {
        case let .blur(blur): blur.enabled?.literalValue != false
        case let .backgroundBlur(blur): blur.enabled?.literalValue != false
        case let .shadow(shadow): shadow.enabled?.literalValue != false
        case .unknown: false
        }
    }
}
