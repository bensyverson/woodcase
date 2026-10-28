//
//  SVGWriter+Silhouette.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A group's silhouette in opaque black: its descendants' combined silhouettes, which
    /// cast its outer and inner shadows.
    ///
    /// - Parameter children: The group's children.
    /// - Returns: The silhouette, in the group's own coordinates.
    func groupSilhouette(of children: [PenNode]) -> SVGElement {
        SVGElement("g", children: descendantSilhouettes(of: children, clip: nil))
    }

    /// A frame's or a group's descendants in opaque black: the part of its silhouette its
    /// children cast — ``PenRenderer/drawDescendantSilhouettes(of:clip:layoutRects:overrides:imageProvider:in:)``
    /// in SVG.
    ///
    /// Built from what each descendant paints rather than its painted element, so a
    /// translucent child casts at full strength, and a child's opacity, blend mode, effects
    /// and own shadows cast nothing. Each casts what it would cast for its own shadow
    /// (``ownSilhouette(_:box:)``), a frame its children with it, cut to its outline when it
    /// clips.
    ///
    /// - Parameters:
    ///   - children: The container's children.
    ///   - clip: The container's outline when it is a frame that clips, else `nil`.
    /// - Returns: The silhouettes, in the container's own coordinates; empty when none casts.
    func descendantSilhouettes(of children: [PenNode], clip: CGPath?) -> [SVGElement] {
        let ink = children.compactMap(silhouette)
        guard !ink.isEmpty, let clip else { return ink }
        let url = define(SVGElement("clipPath", children: [SVGElement("path", ["d": clip.svgPathData])]), prefix: "clip")
        return [SVGElement("g", ["clip-path": url], children: ink)]
    }

    /// What a node's own paint covers, in opaque black and its own coordinates: a shape's
    /// fills and stroke (``PenShadowSilhouette/path(for:rect:)``), or a text's or an icon's
    /// glyphs; `nil` when it covers nothing.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - box: Its draw rect.
    func ownSilhouette(_ node: PenNode, box: PenRect) -> SVGElement? {
        if let outline = PenShadowSilhouette.path(for: node, rect: box) {
            return SVGShape(path: outline.path, rule: outline.rule).element(fill: "#000000")
        }
        switch node.kind {
        case .text:
            return textShape(node, box: box)?.element(fill: "#000000")
        case let .icon(data):
            guard let glyph = PenIconGlyph(data: data, box: CGSize(width: box.width, height: box.height)) else { return nil }
            return SVGShape(path: glyph.outlines().path, rule: .winding).element(fill: "#000000")
        default:
            return nil
        }
    }

    /// One descendant's silhouette, its own and its descendants', placed in its parent's
    /// coordinates, or `nil` when it casts nothing into its container.
    private func silhouette(_ node: PenNode) -> SVGElement? {
        guard PenRenderer.isEnabled(node, overrides: nil), Self.castsIntoContainer(node),
              let rect = layoutRects[node.id]
        else { return nil }
        let placement = PenLayoutEngine.placement(of: node, rect: rect, layoutRects: layoutRects)
        let box = placement.box
        let ink = [ownSilhouette(node, box: box)].compactMap(\.self) + descendantSilhouettes(
            of: node.kind.inlineChildren, clip: PenRenderer.silhouetteClip(of: node, drawRect: box)
        )
        guard !ink.isEmpty else { return nil }
        return SVGElement("g", ["transform": placement.transform == .identity ? nil : placement.transform.svgMatrix], children: ink)
    }

    /// Whether a descendant contributes to its container's silhouette: the kinds with no box
    /// of their own, and a post-it, do not.
    private static func castsIntoContainer(_ node: PenNode) -> Bool {
        switch node.kind {
        case .note, .prompt, .context, .ref, .unknown, .connection: false
        default: true
        }
    }
}
