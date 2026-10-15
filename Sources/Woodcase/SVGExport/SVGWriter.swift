//
//  SVGWriter.swift
//  Woodcase
//

import CoreGraphics
import Foundation

/// One SVG export in progress: walks the roots' subtrees in the CG renderer's paint order
/// and collects the `<defs>` — gradients, clips, masks, filters — their elements refer to.
///
/// A class because the walk shares one growing set of definitions and one id counter, and
/// it lives for one export. ``SVGExporter`` is its public face; the per-kind drawing lives
/// in its extensions, each the twin of a CG renderer file: `+Shape` of
/// `PenRenderer+OwnContent`, `+Paint` of ``PenFillRenderer``, `+Stroke` of
/// ``PenStrokeRenderer``, `+Effects` of ``PenEffectRenderer``, `+Text` of
/// ``PenTextRenderer``, and `+Raster` for what SVG cannot say.
final class SVGWriter {
    /// The expanded, resolved document.
    let document: PenDocument
    /// The settled rects, parent-relative.
    let layoutRects: [String: PenRect]
    /// The region the SVG frames, in the roots' frame: its `viewBox`.
    let bounds: PenRect
    /// Loads the images image fills name.
    let imageProvider: PenRenderer.ImageProvider
    /// How notes, prompts and contexts are drawn, for their embedded pictures.
    let postIt: PenPostIt.DrawingOptions

    /// The definitions written so far, in order.
    private(set) var definitions: [SVGElement] = []
    /// The last id handed out.
    private var counter = 0
    /// Each image fill's embedded data URI, by its URL, so a picture used twice is encoded once.
    var imageData: [String: String] = [:]

    /// Starts an export.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects.
    ///   - bounds: The region the SVG frames.
    ///   - imageProvider: Loads image fills' images.
    ///   - postIt: How notes, prompts and contexts are drawn.
    init(
        document: PenDocument,
        layoutRects: [String: PenRect],
        bounds: PenRect,
        imageProvider: @escaping PenRenderer.ImageProvider,
        postIt: PenPostIt.DrawingOptions
    ) {
        self.document = document
        self.layoutRects = layoutRects
        self.bounds = bounds
        self.imageProvider = imageProvider
        self.postIt = postIt
    }

    /// Adds a definition under a fresh id and answers the `url(#id)` that refers to it.
    ///
    /// - Parameters:
    ///   - element: The definition: a gradient, `clipPath`, `mask` or `filter`.
    ///   - prefix: The id's prefix, which says what it is when the SVG is read.
    /// - Returns: `url(#<id>)`.
    func define(_ element: SVGElement, prefix: String) -> String {
        counter += 1
        var definition = element
        definition["id"] = "\(prefix)\(counter)"
        definitions.append(definition)
        return "url(#\(prefix)\(counter))"
    }

    /// The whole SVG document around `content`: the XML declaration, the root `<svg>`
    /// framing ``bounds`` one unit per point, and the definitions.
    func document(_ content: [SVGElement]) -> String {
        var root = SVGElement("svg", [
            "xmlns": "http://www.w3.org/2000/svg",
            "width": bounds.width.svgNumber,
            "height": bounds.height.svgNumber,
            "viewBox": [bounds.x, bounds.y, bounds.width, bounds.height].map(\.svgNumber).joined(separator: " "),
        ])
        if !definitions.isEmpty {
            root.children.append(SVGElement("defs", children: definitions))
        }
        root.children += content
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + root.xml + "\n"
    }

    /// One root, through its parent's placement and inside its clipping ancestors.
    ///
    /// - Parameter root: The root and what it is seen through.
    /// - Returns: The root's element, or `nil` when it draws nothing.
    func root(_ root: PenCanvasRoot) -> SVGElement? {
        guard var element = node(root.node) else { return nil }
        if root.parentTransform != .identity {
            element = SVGElement("g", ["transform": root.parentTransform.svgMatrix], children: [element])
        }
        for clip in root.clips.reversed() {
            guard let outline = PenShapeBuilder.buildPath(for: clip.node, rect: clip.placement.box) else { continue }
            var toCanvas = clip.placement.transform.cgAffineTransform
            guard let onCanvas = outline.copy(using: &toCanvas) else { continue }
            let url = define(SVGElement("clipPath", children: [SVGElement("path", ["d": onCanvas.svgPathData])]), prefix: "clip")
            element = SVGElement("g", ["clip-path": url], children: [element])
        }
        return element
    }

    /// One node and its subtree, in its parent's coordinates, as `PenRenderer` draws it:
    /// placed, then its own content, then its children — inside its clip when it is a frame
    /// that clips — under its opacity, blend mode and layer blur.
    ///
    /// - Parameter node: The node.
    /// - Returns: The node's element, or `nil` when it draws nothing at all.
    func node(_ node: PenNode) -> SVGElement? {
        guard PenRenderer.isEnabled(node, overrides: nil) else { return nil }
        switch node.kind {
        case .note, .prompt, .context, .browser:
            return rasterNode(node)
        case .connection:
            return rasterConnection(node)
        case .ref, .unknown, .script:
            return nil
        default:
            break
        }
        guard let rect = layoutRects[node.id] else { return nil }
        let placement = PenLayoutEngine.placement(of: node, rect: rect, layoutRects: layoutRects)
        let effects = Effects(PenRenderer.effects(for: node))

        let children = node.kind.inlineChildren.compactMap { self.node($0) }
        var content = ownContent(node, box: placement.box, effects: effects)
        if !children.isEmpty {
            if case let .frame(data) = node.kind, data.clip?.literalValue == true,
               let outline = PenShapeBuilder.buildPath(for: node, rect: placement.box)
            {
                let url = define(SVGElement("clipPath", children: [SVGElement("path", ["d": outline.svgPathData])]), prefix: "clip")
                content.append(SVGElement("g", ["clip-path": url], children: children))
            } else {
                content += children
            }
        }
        if case .group = node.kind {
            content += groupInnerShadows(effects.innerShadows, box: placement.box, of: node.kind.inlineChildren)
        }

        var group = SVGElement("g", ["transform": placement.transform == .identity ? nil : placement.transform.svgMatrix])
        group.children = content
        if let opacity = node.common.opacity?.literalValue, opacity < 1 {
            group["opacity"] = max(0, opacity).svgOpacity
        }
        group["style"] = PenRenderer.blendMode(for: node)?.svgStyle
        if let blur = effects.blur {
            let region = PenLayoutEngine.localPaintedExtent(of: node, box: placement.box, layoutRects: layoutRects)
                ?? placement.box
            group["filter"] = blurFilter(radius: blur, region: region.cgRect)
        }
        return group
    }
}

extension PenLayoutEngine.PlaneTransform {
    /// The map as an SVG `matrix(a b c d e f)`, which shares its coefficients.
    var svgMatrix: String {
        "matrix(" + [a, b, c, d, tx, ty].map(\.svgNumber).joined(separator: " ") + ")"
    }
}
