//
//  FigmaImportSession+Graphics.swift
//  Woodcase
//

extension FigmaImportSession {
    /// What a drawn Pen node paints with: fills, stroke and effects.
    struct Graphics {
        /// The fills.
        var fills: PenFills?
        /// The stroke's paint.
        var stroke: PenFills?
        /// The stroke's width, uniform or per side.
        var strokeWidth: PenStrokeWidth?
        /// The stroke's cap.
        var strokeLinecap: PenStrokeCap?
        /// The stroke's join.
        var strokeLinejoin: PenStrokeJoin?
        /// Where the stroke sits on the outline.
        var strokeAlignment: PenStrokeAlign?
        /// The effects.
        var effects: PenEffects?
    }

    /// The node's fills, stroke and effects. A dash or a shadow spread, which Pen keeps in
    /// `metadata.woodcase`, is written into `common`.
    mutating func graphics(of record: KiwiRecord, common: inout PenNodeCommon) -> Graphics {
        var graphics = Graphics(fills: paints(record["fillPaints"], on: record))
        applyStroke(of: record, to: &graphics, common: &common)
        graphics.effects = effects(of: record, common: &common)
        return graphics
    }

    /// The node's stroke: its paint, width, cap, join, alignment and dash. A node with no
    /// stroke paint has no stroke, whatever its weight says.
    private mutating func applyStroke(of record: KiwiRecord, to graphics: inout Graphics, common: inout PenNodeCommon) {
        guard let stroke = paints(record["strokePaints"], on: record) else { return }
        graphics.stroke = stroke
        let isPerSide = record["borderStrokeWeightsIndependent"]?.boolValue == true
        if isPerSide {
            func side(_ key: String) -> PenValue<Double> {
                .literal(record[key]?.doubleValue ?? 0)
            }
            graphics.strokeWidth = .perSide(PenStrokeWidth.Sides(
                top: side("borderTopWeight"), right: side("borderRightWeight"),
                bottom: side("borderBottomWeight"), left: side("borderLeftWeight")
            ))
        } else {
            graphics.strokeWidth = .uniform(.literal(record["strokeWeight"]?.doubleValue ?? 1))
        }
        graphics.strokeAlignment = switch record["strokeAlign"]?.enumName {
        case "INSIDE": .inner
        case "OUTSIDE": .outer
        default: .center
        }
        graphics.strokeLinejoin = switch record["strokeJoin"]?.enumName {
        case "BEVEL": .bevel
        case "ROUND": .round
        default: .miter
        }
        switch record["strokeCap"]?.enumName {
        case nil, "NONE": graphics.strokeLinecap = .butt
        case "ROUND": graphics.strokeLinecap = .round
        case "SQUARE": graphics.strokeLinecap = .square
        case let cap?:
            graphics.strokeLinecap = .butt
            report(.strokeCap, .approximated, on: record, detail: cap)
        }
        let dash = (record["dashPattern"]?.arrayValue ?? []).compactMap(\.doubleValue)
        guard !dash.isEmpty else { return }
        if isPerSide {
            report(.strokeDash, .dropped, on: record, detail: "per-side widths")
            return
        }
        var metadata = common.metadata ?? PenMetadata(type: nil)
        metadata[woodcase: .strokeDash] = .array(dash.map { .double($0) })
        common.metadata = metadata
    }

    /// The node's effects, bottom first, or `nil` when none maps. A shadow's spread is
    /// written into `common`.
    private mutating func effects(of record: KiwiRecord, common: inout PenNodeCommon) -> PenEffects? {
        var effects: [PenEffect] = []
        var spreads: [PenShadowSpread] = []
        if record["styleIdForEffect"] != nil {
            report(.styleReference, .resolved, on: record, detail: "effect")
        }
        for value in record["effects"]?.arrayValue ?? [] {
            guard let effect = value.recordValue else { continue }
            let enabled: PenValue<Bool>? = effect["visible"]?.boolValue == false ? .literal(false) : nil
            let radius = effect["radius"]?.doubleValue ?? 0
            let type = effect["type"]?.enumName ?? ""
            switch type {
            case "DROP_SHADOW", "INNER_SHADOW":
                let isDrop = type == "DROP_SHADOW"
                let color = FigmaColor(effect["color"]) ?? FigmaColor(red: 0, green: 0, blue: 0, alpha: 0.25)
                let shadow = PenEffect.PenShadowEffect(
                    enabled: enabled, shadowType: isDrop ? .outer : .inner,
                    offset: PenEffect.PenOffset(
                        x: .literal(effect["offset"]?["x"]?.doubleValue ?? 0), y: .literal(effect["offset"]?["y"]?.doubleValue ?? 0)
                    ),
                    blur: .literal(radius), color: .literal(color.hex()),
                    blendMode: effect["blendMode"]?.enumName.flatMap { blendMode(named: $0, on: record) }
                )
                if let spread = effect["spread"]?.doubleValue, spread != 0 {
                    spreads.append(PenShadowSpread(effect: effects.count, spread: spread, shadow: shadow))
                }
                if isDrop, effect["showShadowBehindNode"]?.boolValue == true, hasTranslucentFill(record) {
                    report(.shadowBehindNode, .approximated, on: record)
                }
                effects.append(.shadow(shadow))
            case "FOREGROUND_BLUR", "BACKGROUND_BLUR":
                if effect["blurOpType"]?.enumName == "PROGRESSIVE" {
                    report(.progressiveBlur, .dropped, on: record)
                    continue
                }
                effects.append(type == "FOREGROUND_BLUR"
                    ? .blur(PenEffect.PenBlurEffect(enabled: enabled, radius: .literal(radius)))
                    : .backgroundBlur(PenEffect.PenBackgroundBlurEffect(enabled: enabled, radius: .literal(radius))))
            default:
                report(.unsupportedEffect, .dropped, on: record, detail: type)
            }
        }
        if !spreads.isEmpty {
            var metadata = common.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: .shadowSpread] = PenShadowSpread.metadataValue(of: spreads)
            common.metadata = metadata
        }
        return effects.isEmpty ? nil : .multiple(effects)
    }
}
