//
//  ReactEmitter+ImageCrop.swift
//  Woodcase
//

extension ReactEmitter {
    /// Whether `fill` is an enabled image paint with a crop (a `transform`), which a CSS
    /// background cannot draw: the crop box takes the cropped image's aspect, which only the
    /// running page knows, and the crop may turn or shear the image.
    static func isCroppedImage(_ fill: PenFill) -> Bool {
        guard fill.isEnabled, case let .image(image) = fill else { return false }
        return image.transform != nil
    }

    /// The `<PenImageCrop … />` element that draws a cropped image paint, or `nil` when it
    /// draws nothing: no image yet, or a crop that collapses the image onto a line.
    ///
    /// Cover's crop is written already kept inside the image
    /// (``PenImagePlacement/keptInsideImage(_:)``), so the support file's
    /// ``imageCropSupportFile`` only sizes the crop box from the image's aspect and draws.
    ///
    /// - Parameters:
    ///   - image: The paint.
    ///   - href: The image expression when it is not the paint's own URL — an image prop's
    ///     `{name}` in a component's body.
    ///   - frame: Where the image is laid out inside an SVG pattern, `[x, y, width, height]`;
    ///     `nil` fills the positioned element it is placed in.
    ///   - ctx: The emission context, which records that the file imports `PenImageCrop`.
    static func imageCropElement(
        _ image: PenFill.PenImageFill,
        href: String? = nil,
        frame: [Double]? = nil,
        ctx: EmitContext
    ) -> String? {
        guard let transform = image.transform else { return nil }
        let source: String
        if let href {
            source = href
        } else {
            guard let url = image.url else { return nil }
            source = "\"\(url)\""
        }
        let crop: PenImageTransform
        switch image.placement {
        case .stretch, .contain:
            guard transform.planeTransform.inverted() != nil else { return nil }
            crop = transform
        case .cover:
            guard let kept = PenImagePlacement.keptInsideImage(transform) else { return nil }
            crop = kept
        }
        guard [crop.a, crop.b, crop.c, crop.d, crop.tx, crop.ty].allSatisfy(\.isFinite) else { return nil }
        ctx.usesImageCrop = true
        let coefficients = [crop.a, crop.b, crop.c, crop.d, crop.tx, crop.ty].map { cssNumber($0, decimals: 9) }
        var element = "<PenImageCrop href=\(source) placement=\"\(image.placement.rawValue)\" crop={[\(coefficients.joined(separator: ", "))]}"
        if let frame {
            element += " frame={[\(frame.map { svgNumber($0) }.joined(separator: ", "))]}"
        }
        return element + " />"
    }

    /// The paint server that draws a cropped image paint on a shape React writes as SVG: a
    /// pattern holding the ``imageCropElement(_:href:frame:ctx:)`` over the node's box,
    /// inside a tile `overhang` larger on every side, as an uncropped image's pattern is
    /// (``svgPaint(_:index:shape:overhang:defs:ctx:)``). `nil` for a crop that draws nothing.
    static func svgCropPattern(
        _ image: PenFill.PenImageFill,
        index: Int,
        shape: SVGStrokedShape,
        overhang: Double,
        defs: inout [String],
        ctx: EmitContext
    ) -> String? {
        let box = shape.domain
        guard let element = imageCropElement(image, frame: [overhang, overhang, box.width, box.height], ctx: ctx) else { return nil }
        let id = paintID("wc-paint", shape.nodeID, "\(index)|\(element)")
        defs.append("<pattern id=\"\(id)\" patternUnits=\"userSpaceOnUse\" \(svgRect(box, grownBy: overhang))>")
        defs.append("  \(element)")
        defs.append("</pattern>")
        return "url(#\(id))"
    }

    /// Warns that `node`, a text, draws a cropped image paint uncropped.
    static func warnTextImageCrops(_ node: PenNode, ctx: EmitContext) {
        guard case let .text(data) = node.kind, (data.fills?.all ?? []).contains(where: isCroppedImage) else { return }
        ctx.warnOnce(textImageCropWarning, nodeID: node.id)
    }

    /// The warning for a cropped image paint on text, which React draws uncropped.
    static let textImageCropWarning = "React draws this text's cropped image paint uncropped: "
        + "its glyphs show a CSS background, which cannot crop"
}
