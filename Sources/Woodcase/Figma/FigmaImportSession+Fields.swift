//
//  FigmaImportSession+Fields.swift
//  Woodcase
//

extension FigmaImportSession {
    /// Every node field the importer reads, or knows to be safe to leave: bookkeeping,
    /// publishing state, layout versions and data Figma derives from fields it reads. A
    /// field outside this set, or one of ``fieldsKnownAtDefault`` away from its default, is
    /// reported as ``FigmaImportLoss/Feature/unreadField``, so a field a new Figma release
    /// adds is never dropped silently. A page's own fields (`backgroundEnabled`,
    /// `internalOnly`) are not here: pages are never mapped, so on a layer they are unknown.
    static let knownFields: Set<String> = [
        // Identity, tree and placement. `maskType` only qualifies a mask, which is reported
        // whole; `pluginData` is a plugin's private store and `autoRename` an editor
        // setting, neither drawn.
        "guid", "phase", "parentIndex", "type", "name", "visible", "opacity", "size", "transform", "mask", "maskType",
        "locked", "pluginData", "autoRename",
        // Paint, stroke and effect.
        "fillPaints", "strokePaints", "strokeWeight", "strokeAlign", "strokeCap", "strokeJoin", "dashPattern",
        "borderTopWeight", "borderRightWeight", "borderBottomWeight", "borderLeftWeight", "borderStrokeWeightsIndependent",
        "effects", "blendMode", "cornerRadius", "cornerSmoothing", "rectangleCornerRadiiIndependent",
        "rectangleTopLeftCornerRadius", "rectangleTopRightCornerRadius",
        "rectangleBottomLeftCornerRadius", "rectangleBottomRightCornerRadius",
        // Shapes.
        "arcData", "vectorData", "booleanOperation", "vectorOperationVersion", "count", "countTag", "starInnerScale",
        "starInnerScaleTag",
        // Frames, auto layout and constraints. A child's auto layout settings — absolute
        // positioning, align-self, grow, min and max size, whether borders take space —
        // matter only when its frame reflows, and a frame with `stackMode` is reported as
        // flattened (Figma writes none of them on a child of a frame without one); the
        // positions they produced are the ones the child keeps.
        "frameMaskDisabled", "resizeToFit", "layoutGrids", "horizontalConstraint", "verticalConstraint",
        "stackMode", "stackSpacing", "stackPadding", "stackHorizontalPadding", "stackVerticalPadding",
        "stackPaddingRight", "stackPaddingBottom", "stackPrimarySizing", "stackCounterSizing",
        "stackPrimaryAlignItems", "stackCounterAlignItems", "stackCounterSpacing", "stackWrap", "stackLayoutVersion",
        "stackPositioning", "stackChildAlignSelf", "stackChildPrimaryGrow", "bordersTakeSpace", "minSize", "maxSize",
        // Text. `emojiImageSet` names the emoji artwork Figma draws, which Pen leaves to the
        // system font; `hasHadRTLText` and the version fields are editor bookkeeping.
        "textData", "derivedTextData", "fontName", "fontSize", "lineHeight", "letterSpacing", "textAutoResize",
        "textAlignHorizontal", "textAlignVertical", "textDecoration", "textTruncation", "textCase", "paragraphSpacing",
        "paragraphIndent", "hyperlink", "fontVersion", "emojiImageSet", "textBidiVersion",
        "textExplicitLayoutVersion", "textUserLayoutVersion", "hasHadRTLText",
        // Components and instances.
        "symbolData", "derivedSymbolData", "derivedSymbolDataLayoutVersion", "componentPropDefs",
        "componentPropAssignments", "variantPropSpecs", "isStateGroup", "stateGroupPropertyValueOrders",
        "sharedSymbolVersion", "isSymbolPublishable", "isPublishable", "publishID", "key", "sourceLibraryKey",
        "userFacingVersion", "version", "sortPosition", "styleType",
        // Styles and variables (resolved values travel beside them).
        "styleIdForFill", "styleIdForStrokeFill", "styleIdForText", "styleIdForEffect", "styleIdForGrid",
        "parameterConsumptionMap", "variableModeBySetMap",
    ]

    /// Fields Pen has no property for that change nothing at their default, each with the
    /// test for it: legacy tracking at 0, no variable-font axes, ligatures on, underlines
    /// skipping descenders. Any other value is reported.
    static let fieldsKnownAtDefault: [String: @Sendable (KiwiValue) -> Bool] = [
        "textTracking": { $0.doubleValue == 0 },
        "fontVariations": { $0.arrayValue?.isEmpty == true },
        "fontVariantCommonLigatures": { $0.boolValue == true },
        "fontVariantContextualLigatures": { $0.boolValue == true },
        "textDecorationSkipInk": { $0.boolValue == true },
    ]

    /// Reports each field of `record` the importer neither reads nor knows to leave.
    mutating func reportUnreadFields(of record: KiwiRecord) {
        for (field, value) in record.fields.sorted(by: { $0.key < $1.key }) where !Self.knownFields.contains(field) {
            if let isDefault = Self.fieldsKnownAtDefault[field], isDefault(value) { continue }
            report(.unreadField, .dropped, on: record, detail: field)
        }
    }

    /// Reports what any node may carry that Pen has no place for: constraints, styles,
    /// variable bindings, a pinned variable mode, component properties and variants,
    /// corner smoothing.
    mutating func reportSharedFeatures(of record: KiwiRecord) {
        let constraints = [record["horizontalConstraint"]?.enumName, record["verticalConstraint"]?.enumName]
            .compactMap(\.self).filter { $0 != "MIN" }
        if !constraints.isEmpty {
            report(.constraints, .dropped, on: record, detail: constraints.joined(separator: ", "))
        }
        for (field, detail) in [
            ("styleIdForFill", "fill"), ("styleIdForStrokeFill", "stroke"), ("styleIdForText", "text"), ("styleIdForGrid", "grid"),
        ] where record[field] != nil {
            report(.styleReference, .resolved, on: record, detail: detail)
        }
        for entry in record["parameterConsumptionMap"]?["entries"]?.arrayValue ?? []
            where entry["variableData"]?["value"]?["alias"] != nil
        {
            report(.variableBinding, .resolved, on: record, detail: entry["variableField"]?.enumName)
        }
        if record["variableModeBySetMap"] != nil {
            report(.variableMode, .resolved, on: record)
        }
        if record["isStateGroup"]?.boolValue == true {
            report(.variants, .dropped, on: record)
        } else if !(record["componentPropDefs"]?.arrayValue ?? []).isEmpty {
            report(.componentProperties, .dropped, on: record)
        }
        if let smoothing = record["cornerSmoothing"]?.doubleValue, smoothing > 0 {
            report(.cornerSmoothing, .approximated, on: record)
        }
    }
}
