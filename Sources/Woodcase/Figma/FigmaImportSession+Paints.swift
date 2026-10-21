//
//  FigmaImportSession+Paints.swift
//  Woodcase
//

import Foundation

extension FigmaImportSession {
    /// A paint list — `fillPaints`, `strokePaints` or an override's — as Pen fills, bottom
    /// paint first, or `nil` when none maps.
    mutating func paints(_ value: KiwiValue?, on record: KiwiRecord) -> PenFills? {
        let fills = (value?.arrayValue ?? []).compactMap { paint in
            paint.recordValue.flatMap { self.paint($0, on: record) }
        }
        return fills.isEmpty ? nil : .multiple(fills)
    }

    /// One Figma `Paint` as a Pen fill, or `nil` when Pen has none for it (reported).
    private mutating func paint(_ paint: KiwiRecord, on record: KiwiRecord) -> PenFill? {
        let enabled: PenValue<Bool>? = paint["visible"]?.boolValue == false ? .literal(false) : nil
        let blend = paint["blendMode"]?.enumName.flatMap { blendMode(named: $0, on: record) }
        let opacity = paint["opacity"]?.doubleValue ?? 1
        if paint["colorVar"]?["value"]?["alias"] != nil {
            report(.variableBinding, .resolved, on: record, detail: "paint color")
        }
        let type = paint["type"]?.enumName ?? ""
        switch type {
        case "SOLID":
            let color = FigmaColor(paint["color"]) ?? FigmaColor(red: 0, green: 0, blue: 0, alpha: 1)
            return .color(PenFill.PenColorFill(enabled: enabled, blendMode: blend, color: .literal(color.hex(opacity: opacity))))
        case "GRADIENT_LINEAR", "GRADIENT_RADIAL", "GRADIENT_ANGULAR", "GRADIENT_DIAMOND":
            return .gradient(gradient(paint, type: type, enabled: enabled, blendMode: blend, opacity: opacity, on: record))
        case "IMAGE":
            return image(paint, enabled: enabled, blendMode: blend, opacity: opacity, on: record)
        default:
            report(.unsupportedPaint, .dropped, on: record, detail: type)
            return nil
        }
    }

    /// A gradient paint as a Pen gradient: its stops, and its transform as Pen's center,
    /// size and turn (``FigmaGradientGeometry``).
    private mutating func gradient(
        _ paint: KiwiRecord, type: String, enabled: PenValue<Bool>?, blendMode: PenBlendMode?, opacity: Double,
        on record: KiwiRecord
    ) -> PenFill.PenGradientFill {
        let gradientType: PenGradientType
        switch type {
        case "GRADIENT_LINEAR": gradientType = .linear
        case "GRADIENT_ANGULAR": gradientType = .angular
        case "GRADIENT_DIAMOND":
            gradientType = .radial
            report(.diamondGradient, .approximated, on: record)
        default: gradientType = .radial
        }
        let stops = (paint["stops"]?.arrayValue ?? []).map { stop in
            PenFill.PenGradientStop(
                color: .literal((FigmaColor(stop["color"]) ?? FigmaColor(red: 0, green: 0, blue: 0, alpha: 1)).hex()),
                position: .literal(stop["position"]?.doubleValue ?? 0)
            )
        }
        if (paint["stopsVar"]?.arrayValue ?? []).contains(where: { $0["colorVar"]?["value"]?["alias"] != nil }) {
            report(.variableBinding, .resolved, on: record, detail: "gradient stop")
        }
        var fill = PenFill.PenGradientFill(
            enabled: enabled, blendMode: blendMode, gradientType: gradientType,
            opacity: opacity == 1 ? nil : .literal(opacity), colors: stops
        )
        let transform = FigmaTransform(paint["transform"]) ?? .identity
        guard let geometry = FigmaGradientGeometry(figma: transform) else {
            report(.gradientSkew, .approximated, on: record, detail: "singular transform")
            return fill
        }
        if geometry.isSkewed { report(.gradientSkew, .approximated, on: record) }
        if geometry.centerX != 0.5 || geometry.centerY != 0.5 {
            fill.center = PenFill.PenFillPosition(x: geometry.centerX, y: geometry.centerY)
        }
        if geometry.width != 1 || geometry.height != 1 {
            fill.size = PenFill.PenFillSize(width: .literal(geometry.width), height: .literal(geometry.height))
        }
        if geometry.rotation != 0 { fill.rotation = .literal(geometry.rotation) }
        return fill
    }

    /// An image paint as a Pen image fill, or as ``FigmaImagePlaceholder``'s gray when the
    /// caller named no URL for its hash (reported, with the hash).
    private mutating func image(
        _ paint: KiwiRecord, enabled: PenValue<Bool>?, blendMode: PenBlendMode?, opacity: Double, on record: KiwiRecord
    ) -> PenFill {
        let hash = (paint["image"]?["hash"]?.bytesValue ?? Data()).map { String(format: "%02x", $0) }.joined()
        guard let url = options.imageURLs[hash] else {
            report(.imageNotEmbedded, .placeholder, on: record, detail: hash)
            return .color(FigmaImagePlaceholder.fill(enabled: enabled, blendMode: blendMode, opacity: opacity))
        }
        var fill = PenFill.PenImageFill(enabled: enabled, blendMode: blendMode, opacity: opacity == 1 ? nil : .literal(opacity), url: url)
        switch paint["imageScaleMode"]?.enumName {
        case "FIT": fill.mode = .contain
        case "STRETCH":
            // A crop: Figma's transform maps the box into the image, Pen's the image into the box.
            fill.mode = .stretch
            if let transform = FigmaTransform(paint["transform"]), !transform.isIdentity, let inverse = transform.inverted {
                fill.transform = PenImageTransform(
                    a: inverse.m00, b: inverse.m10, c: inverse.m01, d: inverse.m11, tx: inverse.m02, ty: inverse.m12
                )
            }
        case "TILE":
            fill.mode = .cover
            report(.imageTile, .approximated, on: record)
        default: fill.mode = .cover
        }
        if let rotation = paint["rotation"]?.doubleValue, rotation != 0 {
            report(.unsupportedPaint, .dropped, on: record, detail: "image rotation")
        }
        return .image(fill)
    }

    /// Whether any of the node's visible fills lets what is under it show through.
    func hasTranslucentFill(_ record: KiwiRecord) -> Bool {
        let visible = (record["fillPaints"]?.arrayValue ?? []).filter { $0["visible"]?.boolValue != false }
        guard !visible.isEmpty else { return true }
        return visible.contains { paint in
            let opacity = paint["opacity"]?.doubleValue ?? 1
            switch paint["type"]?.enumName {
            case "SOLID":
                return opacity * (FigmaColor(paint["color"])?.alpha ?? 1) < 1
            case let type? where type.hasPrefix("GRADIENT_"):
                return opacity < 1 || (paint["stops"]?.arrayValue ?? []).contains { (FigmaColor($0["color"])?.alpha ?? 1) < 1 }
            default:
                // An image may hold transparency, and Pen cannot know which.
                return true
            }
        }
    }
}
