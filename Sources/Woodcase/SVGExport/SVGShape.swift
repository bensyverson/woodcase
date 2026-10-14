//
//  SVGShape.swift
//  Woodcase
//

import CoreGraphics

/// The region a paint shows through, in the two forms the SVG writer needs: an element
/// that draws it — a `<path>`, or a `<text>` whose glyphs are the region — and its outline
/// as a `CGPath`, for a paint drawn as an embedded picture and for a clip.
///
/// The SVG twin of ``PenFillRenderer/Target``'s clip. Not ``Friendly``: it holds a `CGPath`,
/// which neither encodes nor hashes, and lives for one paint.
struct SVGShape {
    /// The element that draws the region, with no paint of its own.
    let template: SVGElement
    /// The region's outline.
    let outline: CGPath
    /// How the outline's sub-paths combine.
    let rule: CGPathFillRule

    /// A region that is a path.
    ///
    /// - Parameters:
    ///   - path: The outline.
    ///   - rule: How its sub-paths combine; even-odd makes a nested sub-path a hole.
    init(path: CGPath, rule: CGPathFillRule) {
        template = SVGElement("path", ["d": path.svgPathData, "fill-rule": rule == .evenOdd ? "evenodd" : nil])
        outline = path
        self.rule = rule
    }

    /// A region that is a text's glyphs.
    ///
    /// - Parameters:
    ///   - text: The `<text>` element, its runs set, with no paint.
    ///   - outline: The glyphs' outlines, for what cannot be painted through `<text>`.
    init(text: SVGElement, outline: CGPath) {
        template = text
        self.outline = outline
        rule = .winding
    }

    /// The region drawn in `fill`, a color or a `url(#…)`.
    func element(fill: String) -> SVGElement {
        var element = template
        element["fill"] = fill
        return element
    }

    /// The region as a `clipPath`'s content: a path's rule is its `clip-rule` there.
    var clipContent: SVGElement {
        var element = template
        if element.name == "path" {
            element["clip-rule"] = element["fill-rule"]
            element["fill-rule"] = nil
        }
        return element
    }
}
