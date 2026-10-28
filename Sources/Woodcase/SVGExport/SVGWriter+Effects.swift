//
//  SVGWriter+Effects.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A node's enabled effects, sorted the way the CG renderer reads them.
    struct Effects: Friendly {
        /// The outer shadows, in array order, with their spreads.
        let outerShadows: [PenCastShadow]
        /// The inner shadows, in array order, with their spreads.
        let innerShadows: [PenCastShadow]
        /// The first layer blur's radius, when it blurs at all.
        let blur: Double?

        /// Sorts `node`'s effects; a disabled effect is dropped. A background blur is dropped
        /// too: SVG cannot read what is behind an element (see <doc:PenSVGExport>).
        init(_ node: PenNode) {
            let all = (PenRenderer.effects(for: node)?.all ?? []).filter(\.isEnabled)
            (outerShadows, innerShadows) = PenCastShadow.casts(of: node)
            blur = all.lazy.compactMap { effect -> Double? in
                guard case let .blur(blur) = effect, let radius = blur.radius?.literalValue, radius > 0 else { return nil }
                return radius
            }.first
        }
    }

    /// Each outer shadow cast by `silhouette`, as Pen casts it: blurred, moved, in its color,
    /// and knocked out where the silhouette is, so a translucent fill never shows its own
    /// shadow through it. A spread grows the cast silhouette first (`Cast.morphology(of:)`).
    ///
    /// - Parameters:
    ///   - shadows: The outer shadows, in order, with their spreads.
    ///   - silhouette: What casts them, drawn opaque.
    ///   - region: The silhouette's bounds, in the node's coordinates.
    /// - Returns: One element per shadow: the silhouette, filtered to its shadow alone.
    func outerShadows(
        _ shadows: [PenCastShadow],
        silhouette: SVGElement,
        region: CGRect
    ) -> [SVGElement] {
        shadows.map { entry in
            let shadow = entry.shadow
            let cast = Cast(shadow, spread: entry.spread)
            let filter = SVGElement("filter", cast.region(around: region), children: cast.morphology(of: "SourceAlpha") + [
                SVGElement("feGaussianBlur", ["in": cast.grown("SourceAlpha"), "stdDeviation": cast.deviation.svgNumber]),
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
    ///   - shadows: The inner shadows, in order, with their spreads: a spread grows the
    ///     inverse inward (`Cast.morphology(of:)`).
    ///   - silhouette: The shape they fall inside, drawn opaque.
    ///   - region: The silhouette's bounds, in the node's coordinates.
    /// - Returns: One element per shadow.
    func innerShadows(
        _ shadows: [PenCastShadow],
        silhouette: SVGElement,
        region: CGRect
    ) -> [SVGElement] {
        shadows.map { entry in
            let shadow = entry.shadow
            let cast = Cast(shadow, spread: entry.spread)
            let filter = SVGElement("filter", cast.region(around: region), children: [
                // Ink everywhere the silhouette is not. An `feComponentTransfer` table over
                // `SourceAlpha` says the same, and WebKit draws nothing for it.
                SVGElement("feFlood", ["flood-color": "#000000", "flood-opacity": "1", "result": "ink"]),
                SVGElement("feComposite", ["in": "ink", "in2": "SourceAlpha", "operator": "out", "result": "inverse"]),
            ] + cast.morphology(of: "inverse") + [
                SVGElement("feGaussianBlur", ["in": cast.grown("inverse"), "stdDeviation": cast.deviation.svgNumber]),
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
        _ shadows: [PenCastShadow],
        box: PenRect,
        of children: [PenNode]
    ) -> [SVGElement] {
        guard !shadows.isEmpty, !children.isEmpty else { return [] }
        return innerShadows(shadows, silhouette: groupSilhouette(of: children), region: box.cgRect)
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
        /// How far the cast shape is grown, in points; negative shrinks it.
        let spread: Double

        /// Reads `shadow` in its node's own coordinates.
        ///
        /// Pen turns and flips a node's shadows with it, so the offset is written as
        /// authored: the filter works in the element's own coordinates, which carry the
        /// node's placement and its ancestors'.
        init(_ shadow: PenEffect.PenShadowEffect, spread: CGFloat = 0) {
            self.spread = Double(spread)
            deviation = max(0, shadow.blur?.literalValue ?? 0) / 2
            dx = shadow.offset?.x.literalValue ?? 0
            dy = shadow.offset?.y.literalValue ?? 0
            color = shadow.color?.literalValue.flatMap(PenHexColor.init) ?? PenHexColor(red: 0, green: 0, blue: 0, alpha: 128)
        }

        /// The filter region around `bounds` that holds the whole shadow.
        func region(around bounds: CGRect) -> KeyValuePairs<String, String?> {
            let reach = 3 * deviation + abs(dx) + abs(dy) + max(spread, 0) + 2
            return Self.filterRegion(bounds.insetBy(dx: -reach, dy: -reach))
        }

        /// The primitive that grows `input` by the spread — `feMorphology`, dilating or, for a
        /// negative spread, eroding — with its result named `spread`; nothing for no spread.
        ///
        /// `feMorphology`'s kernel is a square, so a rounded or slanted edge grows square
        /// where the CG renderer grows it along the outline: corners differ by up to the
        /// spread × (√2 − 1).
        ///
        /// - Parameter input: The image to grow.
        /// - Returns: The primitive.
        func morphology(of input: String) -> [SVGElement] {
            guard spread != 0 else { return [] }
            return [SVGElement("feMorphology", [
                "in": input, "operator": spread > 0 ? "dilate" : "erode", "radius": abs(spread).svgNumber,
                "result": "spread",
            ])]
        }

        /// The result the blur reads: `morphology(of:)`'s, or `input` itself for no spread.
        func grown(_ input: String) -> String {
            spread == 0 ? input : "spread"
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
