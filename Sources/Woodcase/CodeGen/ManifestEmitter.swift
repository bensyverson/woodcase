//
//  ManifestEmitter.swift
//  Woodcase
//

import Foundation

/// Generates a `manifest.json` file containing component metadata, theme axes,
/// and variable definitions for use by the preview viewer and external tools.
public enum ManifestEmitter {
    /// Emit a `manifest.json` ``GeneratedFile`` from analyzed components, pages, and theme.
    ///
    /// The manifest is always regenerated (``GeneratedFile/WritePolicy/always``)
    /// because it must reflect the current state of the design document.
    public static func emit(
        components: [ComponentDefinition],
        pages: [PageDefinition],
        theme: ThemeManifest
    ) -> GeneratedFile {
        var root: [String: Any] = [:]

        // Components
        let componentEntries: [[String: Any]] = components.map { component in
            var entry: [String: Any] = [
                "name": component.name,
                "path": "components/\(component.name)",
            ]
            let props: [[String: String]] = component.props.map { prop in
                ["name": prop.name, "type": prop.type.rawValue]
            }
            entry["props"] = props
            if let role = component.role {
                entry["role"] = role.rawValue
            }
            if !component.states.isEmpty {
                entry["states"] = component.states.map(\.name)
            }
            return entry
        }
        root["components"] = componentEntries

        // Pages
        let pageEntries: [[String: Any]] = pages.map { page in
            [
                "name": page.name,
                "path": "pages/\(page.name)",
            ]
        }
        root["pages"] = pageEntries

        // Theme
        var themeDict: [String: Any] = [:]

        let axisEntries: [[String: Any]] = theme.axes.map { axis in
            ["name": axis.name, "values": axis.values]
        }
        themeDict["axes"] = axisEntries

        let variableEntries: [[String: Any]] = theme.variables.map { variable in
            var values: [String: Any] = [:]
            for themed in variable.values {
                let key = conditionKey(for: themed.conditions)
                values[key] = anyCodableToJSONValue(themed.value)
            }
            return [
                "name": variable.name,
                "type": variable.type.rawValue,
                "values": values,
            ] as [String: Any]
        }
        themeDict["variables"] = variableEntries

        root["theme"] = themeDict

        // Serialize
        let content = if let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            String(data: data, encoding: .utf8) ?? "{}"
        } else {
            "{}"
        }

        return GeneratedFile(path: "manifest.json", content: content)
    }

    // MARK: - Private

    /// Build a condition key string from a conditions dictionary.
    /// Empty conditions → `"default"`, single condition → `"axis:value"`.
    private static func conditionKey(for conditions: [String: String]) -> String {
        if conditions.isEmpty {
            return "default"
        }
        return conditions
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }

    /// Convert an ``AnyCodable`` value to a JSON-compatible `Any`.
    private static func anyCodableToJSONValue(_ value: AnyCodable) -> Any {
        switch value {
        case .null:
            NSNull()
        case let .bool(b):
            b
        case let .int(i):
            i
        case let .double(d):
            d
        case let .string(s):
            s
        case let .array(arr):
            arr.map { anyCodableToJSONValue($0) }
        case let .dictionary(dict):
            dict.mapValues { anyCodableToJSONValue($0) }
        }
    }
}
