//
//  SVGWriter+Paint.swift
//  Woodcase
//

import CoreGraphics
import Foundation

extension SVGWriter {
    /// Every enabled fill, bottom to top, each its own element through `shape`, laid out
    /// over `domain` — ``PenFillRenderer/renderFills(_:clip:fillRule:domain:in:imageProvider:)``
    /// in SVG.
    ///
    /// A solid color is the element's `fill`; a linear or radial gradient a
    /// `userSpaceOnUse` gradient whose `gradientTransform` is the CG renderer's gradient
    /// frame, so its stops land where Pen puts them on the box; an image fill its pixels,
    /// embedded, placed by its mode and crop and clipped to the shape. An angular or mesh
    /// gradient, which SVG has no element for, is embedded as the CG renderer's picture of
    /// that one paint. A shader fill draws nothing, as in the CG renderer.
    ///
    /// - Parameters:
    ///   - fills: The fills; `nil` draws nothing.
    ///   - shape: The region they show through.
    ///   - domain: The rectangle the paint is laid out over: the node's box.
    /// - Returns: One element per drawn fill.
    func paint(_ fills: PenFills?, through shape: SVGShape, domain: CGRect) -> [SVGElement] {
        guard let fills else { return [] }
        var clip: String?
        func clipURL() -> String {
            if let clip { return clip }
            let url = define(SVGElement("clipPath", children: [shape.clipContent]), prefix: "clip")
            clip = url
            return url
        }
        return fills.all.compactMap { fill in
            layer(fill, through: shape, domain: domain, clip: clipURL)
        }
    }

    /// One fill through `shape`, or `nil` when it draws nothing.
    private func layer(_ fill: PenFill, through shape: SVGShape, domain: CGRect, clip: () -> String) -> SVGElement? {
        switch fill {
        case let .shorthand(hex):
            return PenHexColor(hex).map { shape.paintedSolid($0, blend: nil) }
        case let .color(color):
            guard color.enabled?.literalValue != false,
                  let hex = color.color.literalValue.flatMap(PenHexColor.init)
            else { return nil }
            return shape.paintedSolid(hex, blend: color.blendMode)
        case let .gradient(gradient):
            guard gradient.enabled?.literalValue != false else { return nil }
            if gradient.gradientType == .angular {
                return rasterPaint(fill, through: shape, domain: domain, blend: gradient.blendMode)
            }
            guard let url = gradientDefinition(gradient, domain: domain) else { return nil }
            var element = shape.element(fill: url)
            if let opacity = gradient.opacity?.literalValue, opacity < 1 {
                element["fill-opacity"] = max(0, opacity).svgOpacity
            }
            element["style"] = gradient.blendMode?.svgStyle
            return element
        case let .image(image):
            guard image.enabled?.literalValue != false else { return nil }
            return imageLayer(image, domain: domain, clip: clip())
        case let .meshGradient(mesh):
            guard mesh.enabled?.literalValue != false else { return nil }
            return rasterPaint(fill, through: shape, domain: domain, blend: mesh.blendMode)
        case .shader, .unknown:
            return nil
        }
    }

    /// A linear or radial gradient's definition, or `nil` when it has no stop that parses
    /// or its frame collapses.
    ///
    /// In the gradient's own unit space a linear gradient runs from `(0, 0.5)` to
    /// `(0, -0.5)` and a radial one from the origin out to radius 0.5;
    /// ``PenFill/PenGradientFill/frameTransform(in:)`` carries that space onto the box —
    /// the same map the CG renderer concatenates before it draws.
    ///
    /// - Returns: `url(#…)` for the definition.
    func gradientDefinition(_ gradient: PenFill.PenGradientFill, domain: CGRect) -> String? {
        let stops = (gradient.colors ?? []).compactMap { stop -> (position: Double, color: PenHexColor)? in
            guard let hex = stop.color.literalValue.flatMap(PenHexColor.init) else { return nil }
            return (stop.position.literalValue ?? 0, hex)
        }
        let frame = gradient.frameTransform(in: domain)
        guard !stops.isEmpty, abs(frame.a * frame.d - frame.b * frame.c) > 1e-12 else { return nil }
        var element = switch gradient.gradientType ?? .linear {
        case .radial:
            SVGElement("radialGradient", ["cx": "0", "cy": "0", "r": "0.5"])
        case .linear, .angular:
            SVGElement("linearGradient", ["x1": "0", "y1": "0.5", "x2": "0", "y2": "-0.5"])
        }
        element["gradientUnits"] = "userSpaceOnUse"
        element["gradientTransform"] = frame.svgMatrix
        element.children = stops.map { stop in
            SVGElement("stop", [
                "offset": min(1, max(0, stop.position)).svgNumber,
                "stop-color": stop.color.svgColor,
                "stop-opacity": stop.color.alpha == 255 ? nil : stop.color.svgAlpha,
            ])
        }
        return define(element, prefix: "paint")
    }

    /// An image fill: its pixels embedded as PNG, placed by its mode and crop over the
    /// domain, clipped to the shape — and to the crop box for a `fit` image.
    private func imageLayer(_ fill: PenFill.PenImageFill, domain: CGRect, clip: String) -> SVGElement? {
        guard let url = fill.url, let image = imageProvider(url),
              let placed = PenImagePlacement(
                  bounds: PenRect(x: domain.minX, y: domain.minY, width: domain.width, height: domain.height),
                  imageSize: PenSize(width: Double(image.width), height: Double(image.height)),
                  fill: fill
              ),
              let href = imageData[url] ?? dataURI(image)
        else { return nil }
        imageData[url] = href
        var picture = SVGElement("image", [
            "width": "1", "height": "1", "preserveAspectRatio": "none",
            "transform": placed.imageTransform.svgMatrix, "href": href,
        ])
        if let clipRect = placed.clipRect {
            let rect = SVGElement("rect", [
                "x": clipRect.x.svgNumber, "y": clipRect.y.svgNumber,
                "width": clipRect.width.svgNumber, "height": clipRect.height.svgNumber,
            ])
            picture = SVGElement("g", ["clip-path": define(SVGElement("clipPath", children: [rect]), prefix: "clip")], children: [picture])
        }
        var layer = SVGElement("g", ["clip-path": clip], children: [picture])
        if let opacity = fill.opacity?.literalValue, opacity < 1 {
            layer["opacity"] = max(0, opacity).svgOpacity
        }
        layer["style"] = fill.blendMode?.svgStyle
        return layer
    }

    /// An image as a PNG data URI, or `nil` when it cannot be encoded.
    func dataURI(_ image: CGImage) -> String? {
        (try? PNGEncoder.encode(image)).map { "data:image/png;base64," + $0.base64EncodedString() }
    }
}

extension SVGShape {
    /// The shape filled with one solid color, its alpha as `fill-opacity`.
    func paintedSolid(_ color: PenHexColor, blend: PenBlendMode?) -> SVGElement {
        var element = element(fill: color.svgColor)
        if color.alpha != 255 {
            element["fill-opacity"] = color.svgAlpha
        }
        element["style"] = blend?.svgStyle
        return element
    }
}

extension PenHexColor {
    /// The color's RGB as SVG writes it: `#rrggbb`, lowercase, no alpha.
    var svgColor: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }

    /// The color's alpha as an SVG opacity.
    var svgAlpha: String {
        (Double(alpha) / 255).svgOpacity
    }
}

extension CGAffineTransform {
    /// The transform as an SVG `matrix(a b c d e f)`.
    var svgMatrix: String {
        "matrix(" + [a, b, c, d, tx, ty].map { Double($0).svgNumber }.joined(separator: " ") + ")"
    }
}
