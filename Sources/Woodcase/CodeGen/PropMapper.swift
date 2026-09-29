//
//  PropMapper.swift
//  Woodcase
//

/// Maps a ref's descendant overrides to prop values using a component's prop definitions.
///
/// Each override key is a node ID. `PropMapper` uses the component's
/// ``ComponentDefinition/propsByNodeID`` lookup to match overrides to props, then
/// extracts the appropriate value based on each prop's type. The values are typed, not
/// formatted: each emitter writes them in its own syntax (React as JSX attribute values).
///
/// One override can feed several props, because one descendant can carry several: a
/// `label` reading a text node's content and a `tint` reading its fill are two readings
/// of the same node and the same override, and both become attributes. Two props of the
/// same *type* on one node read the same field and are ambiguous — there is no way to
/// tell which the author meant — so only the first by prop name is emitted, and `lint`
/// reports the pair under `codegen-prop-path` with the edit that separates them.
public enum PropMapper {
    /// A prop's value, read from an override, one case per ``PropType``.
    public enum Value: Friendly {
        /// A text node's content.
        case string(String)

        /// A solid fill's color: a literal such as `#FF5500`, or a document variable.
        case color(PenValue<String>)

        /// A node's `enabled` flag.
        case boolean(Bool)

        /// An image fill's URL, as written in the document.
        case imageURL(String)
    }

    /// A mapped prop, ready for an emitter to format.
    public struct MappedProp: Friendly {
        /// The prop name (e.g., "title").
        public var name: String

        /// The value the override gives the prop.
        public var value: Value
    }

    /// Map descendant overrides to prop values for the given component.
    ///
    /// - Parameters:
    ///   - overrides: The instance's `descendants` map, keyed by descendant node id.
    ///   - component: The definition the instance names.
    /// - Returns: One value per prop that both names an overridden descendant and
    ///   finds its own field in that override, in prop-name order. Where several props
    ///   of one node share a type, only the first by name is here.
    public static func map(
        overrides: [String: PenDescendantOverride],
        to component: ComponentDefinition
    ) -> [MappedProp] {
        let lookup = component.propsByNodeID
        var results: [MappedProp] = []

        for (nodeID, override) in overrides {
            guard let props = lookup[nodeID] else { continue }
            var claimed: Set<PropType> = []

            for prop in props where !claimed.contains(prop.type) {
                claimed.insert(prop.type)
                if let value = extractValue(from: override, for: prop.type) {
                    results.append(MappedProp(name: prop.name, value: value))
                }
            }
        }

        return results.sorted { $0.name < $1.name }
    }

    // MARK: - Value Extraction

    private static func extractValue(
        from override: PenDescendantOverride,
        for propType: PropType
    ) -> Value? {
        switch propType {
        case .string:
            extractString(from: override)
        case .color:
            extractColor(from: override)
        case .boolean:
            extractBoolean(from: override)
        case .imageURL:
            extractImageURL(from: override)
        }
    }

    private static func extractString(from override: PenDescendantOverride) -> Value? {
        guard case let .string(content) = override.properties["content"] else { return nil }
        return .string(content)
    }

    private static func extractColor(from override: PenDescendantOverride) -> Value? {
        switch override.properties["fill"] {
        // Shorthand: a bare color string like "#FF5500" or "$varName"
        case let .string(value):
            .color(colorValue(value))
        // Object fill: { type: "color", color: "#hex" or "$var" }
        case let .dictionary(dict):
            if case let .string(value) = dict["color"] { .color(colorValue(value)) } else { nil }
        default:
            nil
        }
    }

    /// A color as the document spells it: `$name` is a variable, anything else a literal.
    private static func colorValue(_ spelling: String) -> PenValue<String> {
        spelling.hasPrefix("$") ? .variable(String(spelling.dropFirst())) : .literal(spelling)
    }

    private static func extractBoolean(from override: PenDescendantOverride) -> Value? {
        guard case let .bool(value) = override.properties["enabled"] else { return nil }
        return .boolean(value)
    }

    private static func extractImageURL(from override: PenDescendantOverride) -> Value? {
        guard case let .dictionary(dict) = override.properties["fill"],
              case let .string(url) = dict["url"]
        else { return nil }
        return .imageURL(url)
    }
}
