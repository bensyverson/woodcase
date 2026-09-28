//
//  NodeDiffer.swift
//  Woodcase
//

/// Compares base and variant PenNode trees, producing platform-neutral property deltas.
public enum NodeDiffer {
    /// The result of diffing a base node tree against a variant.
    public struct DiffResult: Friendly {
        public init(deltas: [StateDelta], isStructural: Bool) {
            self.deltas = deltas
            self.isStructural = isStructural
        }

        /// Property changes grouped by node path.
        public var deltas: [StateDelta]

        /// Whether the variant has structural changes (added/removed/reordered children).
        public var isStructural: Bool
    }

    /// Diff a base node against a variant node.
    public static func diff(base: PenNode, variant: PenNode) -> DiffResult {
        var deltas: [StateDelta] = []
        var isStructural = false
        diffNode(base: base, variant: variant, path: ".", deltas: &deltas, isStructural: &isStructural)
        return DiffResult(deltas: deltas, isStructural: isStructural)
    }

    // MARK: - Recursive Diff

    private static func diffNode(
        base: PenNode,
        variant: PenNode,
        path: String,
        deltas: inout [StateDelta],
        isStructural: inout Bool
    ) {
        // Compare visual properties at this node
        let changes = compareProperties(base: base, variant: variant)
        if !changes.isEmpty {
            deltas.append(StateDelta(nodePath: path, changes: changes))
        }

        // Compare children
        let baseChildren = children(of: base)
        let variantChildren = children(of: variant)

        // Build name-indexed lookups
        let baseByName: [(String, PenNode)] = baseChildren.compactMap { node in
            guard let name = node.common.name else { return nil }
            return (name, node)
        }
        let variantByName: [(String, PenNode)] = variantChildren.compactMap { node in
            guard let name = node.common.name else { return nil }
            return (name, node)
        }

        let baseNames = baseByName.map(\.0)
        let variantNames = variantByName.map(\.0)
        let baseNameSet = Set(baseNames)
        let variantNameSet = Set(variantNames)

        // Structural detection: added, removed, or reordered children
        if baseNameSet != variantNameSet {
            isStructural = true
        } else {
            // Same set of names — check order
            let matchedBaseOrder = baseNames.filter { variantNameSet.contains($0) }
            let matchedVariantOrder = variantNames.filter { baseNameSet.contains($0) }
            if matchedBaseOrder != matchedVariantOrder {
                isStructural = true
            }
        }

        // Recurse into matched children
        let baseLookup = Dictionary(baseByName, uniquingKeysWith: { first, _ in first })
        let variantLookup = Dictionary(variantByName, uniquingKeysWith: { first, _ in first })

        for name in baseNames where variantLookup[name] != nil {
            let baseChild = baseLookup[name]!
            let variantChild = variantLookup[name]!

            // Positional changes (x/y) on children indicate structural differences
            // since they can't be expressed as CSS custom property overrides.
            if baseChild.common.x != variantChild.common.x
                || baseChild.common.y != variantChild.common.y
            {
                isStructural = true
            }

            let childPath = path == "." ? name : "\(path)/\(name)"
            diffNode(
                base: baseChild,
                variant: variantChild,
                path: childPath,
                deltas: &deltas,
                isStructural: &isStructural
            )
        }
    }

    // MARK: - Property Comparison

    private static func compareProperties(base: PenNode, variant: PenNode) -> [PropertyChange] {
        var changes: [PropertyChange] = []

        // Common properties
        if base.common.opacity != variant.common.opacity {
            changes.append(PropertyChange(
                property: .opacity,
                value: encodeValue(variant.common.opacity)
            ))
        }

        if base.common.rotation != variant.common.rotation
            || base.common.flipX != variant.common.flipX
            || base.common.flipY != variant.common.flipY
        {
            changes.append(PropertyChange(transform: DeltaTransform(of: variant.common)))
        }

        // Kind-specific properties
        switch (base.kind, variant.kind) {
        case let (.frame(baseData), .frame(variantData)):
            compareFrameProperties(base: baseData, variant: variantData, into: &changes)

        case let (.rectangle(baseData), .rectangle(variantData)):
            compareRectProperties(base: baseData, variant: variantData, into: &changes)

        case let (.ellipse(baseData), .ellipse(variantData)):
            compareEllipseProperties(base: baseData, variant: variantData, into: &changes)

        case let (.text(baseData), .text(variantData)):
            compareTextProperties(base: baseData, variant: variantData, into: &changes)

        case let (.polygon(baseData), .polygon(variantData)):
            comparePolygonProperties(base: baseData, variant: variantData, into: &changes)

        default:
            break
        }

        return changes
    }

    // MARK: - Frame

    private static func compareFrameProperties(
        base: PenNode.FrameData,
        variant: PenNode.FrameData,
        into changes: inout [PropertyChange]
    ) {
        if base.fills != variant.fills {
            changes.append(PropertyChange(property: .fills, value: encodeFills(variant.fills)))
        }
        compareStroke(base: base, variant: variant, into: &changes)
        if base.cornerRadius != variant.cornerRadius {
            changes.append(PropertyChange(property: .cornerRadius, value: encodeCornerRadius(variant.cornerRadius)))
        }
        if base.effects != variant.effects {
            compareEffects(variant: variant.effects, into: &changes)
        }
        if base.width != variant.width {
            changes.append(PropertyChange(property: .width, value: encodeSizing(variant.width)))
        }
        if base.height != variant.height {
            changes.append(PropertyChange(property: .height, value: encodeSizing(variant.height)))
        }
        if base.padding != variant.padding {
            changes.append(PropertyChange(property: .padding, value: encodePadding(variant.padding)))
        }
        if base.gap != variant.gap {
            changes.append(PropertyChange(property: .gap, value: encodeValue(variant.gap)))
        }
    }

    // MARK: - Rectangle

    private static func compareRectProperties(
        base: PenNode.RectangleData,
        variant: PenNode.RectangleData,
        into changes: inout [PropertyChange]
    ) {
        if base.fills != variant.fills {
            changes.append(PropertyChange(property: .fills, value: encodeFills(variant.fills)))
        }
        compareStroke(base: base, variant: variant, into: &changes)
        if base.cornerRadius != variant.cornerRadius {
            changes.append(PropertyChange(property: .cornerRadius, value: encodeCornerRadius(variant.cornerRadius)))
        }
        if base.effects != variant.effects {
            compareEffects(variant: variant.effects, into: &changes)
        }
        if base.width != variant.width {
            changes.append(PropertyChange(property: .width, value: encodeSizing(variant.width)))
        }
        if base.height != variant.height {
            changes.append(PropertyChange(property: .height, value: encodeSizing(variant.height)))
        }
    }

    // MARK: - Ellipse

    private static func compareEllipseProperties(
        base: PenNode.EllipseData,
        variant: PenNode.EllipseData,
        into changes: inout [PropertyChange]
    ) {
        if base.fills != variant.fills {
            changes.append(PropertyChange(property: .fills, value: encodeFills(variant.fills)))
        }
        compareStroke(base: base, variant: variant, into: &changes)
        if base.effects != variant.effects {
            compareEffects(variant: variant.effects, into: &changes)
        }
        if base.width != variant.width {
            changes.append(PropertyChange(property: .width, value: encodeSizing(variant.width)))
        }
        if base.height != variant.height {
            changes.append(PropertyChange(property: .height, value: encodeSizing(variant.height)))
        }
    }

    // MARK: - Text

    private static func compareTextProperties(
        base: PenNode.TextData,
        variant: PenNode.TextData,
        into changes: inout [PropertyChange]
    ) {
        // For text nodes, fills represent text color
        if base.fills != variant.fills {
            changes.append(PropertyChange(property: .textColor, value: encodeFills(variant.fills)))
        }
        if base.fontSize != variant.fontSize {
            changes.append(PropertyChange(property: .fontSize, value: encodeValue(variant.fontSize)))
        }
        if base.fontWeight != variant.fontWeight {
            changes.append(PropertyChange(property: .fontWeight, value: encodeStringValue(variant.fontWeight)))
        }
        compareStroke(base: base, variant: variant, into: &changes)
        if base.effects != variant.effects {
            compareEffects(variant: variant.effects, into: &changes)
        }
    }

    // MARK: - Polygon

    private static func comparePolygonProperties(
        base: PenNode.PolygonData,
        variant: PenNode.PolygonData,
        into changes: inout [PropertyChange]
    ) {
        if base.fills != variant.fills {
            changes.append(PropertyChange(property: .fills, value: encodeFills(variant.fills)))
        }
        compareStroke(base: base, variant: variant, into: &changes)
        if base.cornerRadius != variant.cornerRadius {
            changes.append(PropertyChange(property: .cornerRadius, value: encodeCornerRadius(variant.cornerRadius)))
        }
        if base.effects != variant.effects {
            compareEffects(variant: variant.effects, into: &changes)
        }
    }

    // MARK: - Shared Comparisons

    private static func compareStroke(
        base: any PenStrokable,
        variant: any PenStrokable,
        into changes: inout [PropertyChange]
    ) {
        if base.stroke != variant.stroke {
            changes.append(PropertyChange(property: .strokeColor, value: encodeFills(variant.stroke)))
        }
        if base.strokeWidth != variant.strokeWidth {
            changes.append(PropertyChange(property: .strokeWidth, value: encodeStrokeWidth(variant.strokeWidth)))
        }
    }

    private static func compareEffects(
        variant: PenEffects?,
        into changes: inout [PropertyChange]
    ) {
        // Encode shadow and blur changes from effects
        // Since effects are compared as a whole, we emit both if effects differ
        let effects = variant?.all ?? []
        let hasShadow = effects.contains { if case .shadow = $0 { true } else { false } }
        let hasBlur = effects.contains { if case .blur = $0 { true } else { false } }

        if hasShadow {
            changes.append(PropertyChange(property: .shadow, value: encodeEffects(variant)))
        }
        if hasBlur {
            changes.append(PropertyChange(property: .blur, value: encodeEffects(variant)))
        }
        if !hasShadow, !hasBlur {
            // Effects removed or only contain other types
            changes.append(PropertyChange(property: .shadow, value: .null))
        }
    }

    // MARK: - Children

    private static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }

    // MARK: - Value Encoding

    private static func encodeValue(_ value: PenValue<Double>?) -> AnyCodable {
        guard let value else { return AnyCodable.null }
        switch value {
        case let .literal(v): return AnyCodable.double(v)
        case let .variable(name): return AnyCodable.string("$\(name)")
        }
    }

    private static func encodeStringValue(_ value: PenValue<String>?) -> AnyCodable {
        guard let value else { return AnyCodable.null }
        switch value {
        case let .literal(v): return AnyCodable.string(v)
        case let .variable(name): return AnyCodable.string("$\(name)")
        }
    }

    private static func encodeFills(_ fills: PenFills?) -> AnyCodable {
        guard let fills else { return .null }
        // Encode fills as a simplified representation
        let allFills = fills.all
        if allFills.count == 1, let fill = allFills.first {
            switch fill {
            case let .shorthand(color):
                return .string(color)
            case let .color(colorFill):
                if let literal = colorFill.color.literalValue {
                    return .string(literal)
                }
                if let varName = colorFill.color.variableName {
                    return .string("$\(varName)")
                }
                return .string("color")
            default:
                return .string("complex-fill")
            }
        }
        return .string("multi-fill")
    }

    private static func encodeSizing(_ sizing: PenSizing?) -> AnyCodable {
        guard let sizing else { return AnyCodable.null }
        switch sizing {
        case let .fixed(v): return AnyCodable.double(v)
        case .fitContent: return AnyCodable.string("fit-content")
        case .fillContainer: return AnyCodable.string("fill-container")
        case let .variable(name): return AnyCodable.string("$\(name)")
        }
    }

    private static func encodeCornerRadius(_ radius: PenCornerRadius?) -> AnyCodable {
        guard let radius else { return AnyCodable.null }
        switch radius {
        case let .uniform(value): return encodeValue(value)
        case .perCorner: return AnyCodable.string("per-corner")
        }
    }

    private static func encodePadding(_ padding: PenPadding?) -> AnyCodable {
        guard let padding else { return AnyCodable.null }
        switch padding {
        case let .uniform(value): return encodeValue(value)
        case .symmetric: return AnyCodable.string("symmetric")
        case .individual: return AnyCodable.string("individual")
        }
    }

    private static func encodeStrokeWidth(_ width: PenStrokeWidth?) -> AnyCodable {
        guard let width else { return AnyCodable.null }
        switch width {
        case let .uniform(value): return encodeValue(value)
        case .perSide: return AnyCodable.string("per-side")
        }
    }

    private static func encodeEffects(_ effects: PenEffects?) -> AnyCodable {
        guard effects != nil else { return .null }
        return .string("effects")
    }
}
