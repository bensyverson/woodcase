//
//  SVGWriter+Silhouette.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A group's silhouette in opaque black: its descendants' combined outline, which casts
    /// its outer and inner shadows — ``PenRenderer/drawDescendantSilhouettes(of:clip:layoutRects:overrides:imageProvider:in:)``
    /// in SVG.
    ///
    /// Built from the descendants' outlines rather than their painted elements, so a
    /// translucent child casts at full strength and a child's opacity and own shadow cast
    /// nothing. Each shape casts what its own paint covers (``PenShadowSilhouette/path(for:rect:)``),
    /// but a frame's children and a line still cast nothing here, as Pen 1.2.16 cast them;
    /// Pen CLI 0.3.13 casts both, as the Core Graphics renderer does.
    ///
    /// - Parameter children: The group's children.
    /// - Returns: The silhouette, in the group's own coordinates.
    func groupSilhouette(of children: [PenNode]) -> SVGElement {
        SVGElement("g", children: children.compactMap(silhouette))
    }

    /// One descendant's silhouette, placed in its parent's coordinates, or `nil` when it
    /// casts nothing into its group.
    private func silhouette(_ node: PenNode) -> SVGElement? {
        guard PenRenderer.isEnabled(node, overrides: nil), Self.castsIntoGroup(node),
              let rect = layoutRects[node.id]
        else { return nil }
        let placement = PenLayoutEngine.placement(of: node, rect: rect, layoutRects: layoutRects)
        let box = placement.box
        let ink: [SVGElement] = if case .group = node.kind {
            node.kind.inlineChildren.compactMap(silhouette)
        } else if let outline = PenShadowSilhouette.path(for: node, rect: box) {
            [SVGShape(path: outline.path, rule: outline.rule).element(fill: "#000000")]
        } else if case .text = node.kind, let text = textShape(node, box: box) {
            [text.element(fill: "#000000")]
        } else if case let .icon(data) = node.kind,
                  let glyph = PenIconGlyph(data: data, box: CGSize(width: box.width, height: box.height))
        {
            [SVGShape(path: glyph.outlines().path, rule: .winding).element(fill: "#000000")]
        } else {
            []
        }
        guard !ink.isEmpty else { return nil }
        return SVGElement("g", ["transform": placement.transform == .identity ? nil : placement.transform.svgMatrix], children: ink)
    }

    /// Whether a descendant contributes to its group's silhouette: a line and the kinds
    /// with no box of their own do not.
    private static func castsIntoGroup(_ node: PenNode) -> Bool {
        switch node.kind {
        case .line, .note, .prompt, .context, .ref, .unknown, .connection: false
        default: true
        }
    }
}
