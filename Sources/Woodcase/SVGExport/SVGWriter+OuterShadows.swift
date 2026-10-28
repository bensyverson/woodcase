//
//  SVGWriter+OuterShadows.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A node's outer shadows, cast by what it paints as the CG renderer casts them
    /// (``PenShadowSilhouette``): its own silhouette united with a frame's or a group's
    /// descendants' (``descendantSilhouettes(of:clip:)``), cut where a frame clips, as one
    /// element, so the pieces cast one shadow from their union.
    ///
    /// A spread grows only the node's own path, along its outline, as
    /// ``PenShadowSilhouette/spread(_:rule:by:)`` grows it; glyphs and descendants cast as
    /// they are. The shadow is knocked out under the ungrown silhouette: by the filter itself
    /// when nothing was grown, and by a mask of the ungrown silhouette when something was.
    ///
    /// - Parameters:
    ///   - shadows: The node's outer shadows, in order, with their spreads.
    ///   - node: The node.
    ///   - box: Its draw rect, in its own coordinates.
    ///   - glyphs: A text's or an icon's glyphs in opaque black and their bounds, which a
    ///     caller that has laid them out passes in; `nil` to build the node's own silhouette
    ///     (``ownSilhouette(_:box:)``).
    /// - Returns: One element per shadow, bottom first; empty when the node casts nothing.
    func outerShadows(
        _ shadows: [PenCastShadow],
        of node: PenNode,
        box: PenRect,
        glyphs: (ink: SVGElement, bounds: CGRect)? = nil
    ) -> [SVGElement] {
        guard !shadows.isEmpty else { return [] }
        let children = node.kind.inlineChildren
        let clip = PenRenderer.silhouetteClip(of: node, drawRect: box)
        let descendants = descendantSilhouettes(of: children, clip: clip)
        let outline = PenShadowSilhouette.path(for: node, rect: box)
        let own: SVGElement? = glyphs?.ink ?? ownSilhouette(node, box: box)
        guard own != nil || !descendants.isEmpty else { return [] }

        var region = glyphs?.bounds ?? outline?.path.boundingBoxOfPath ?? .null
        if own != nil, glyphs == nil, outline == nil {
            region = box.cgRect
        }
        if !descendants.isEmpty, let bounds = PenRenderer.descendantSilhouetteBounds(
            of: children, clipsTo: clip.map { _ in box.cgRect }, layoutRects: layoutRects
        ) {
            region = region.union(bounds)
        }
        guard !region.isNull else { return [] }

        /// The filter goes on a plain group around the descendants: on a descendant's own
        /// element it would work in that child's coordinates, and a clip there would cut
        /// the shadow, which SVG clips after filtering.
        func ink(_ ownInk: SVGElement?) -> SVGElement {
            guard let ownInk, descendants.isEmpty else {
                return SVGElement("g", children: [ownInk].compactMap(\.self) + descendants)
            }
            return ownInk
        }
        let ungrown = ink(own)
        return shadows.map { entry in
            guard entry.spread != 0, let outline else {
                return outerShadow(entry.shadow, silhouette: ungrown, knockout: nil, region: region)
            }
            let grown = PenShadowSilhouette.spread(outline.path, rule: outline.rule, by: entry.spread)
            let grownInk = SVGShape(path: grown.path, rule: grown.rule).element(fill: "#000000")
            return outerShadow(
                entry.shadow, silhouette: ink(grownInk), knockout: ungrown,
                region: region.union(grown.path.boundingBoxOfPath)
            )
        }
    }
}
