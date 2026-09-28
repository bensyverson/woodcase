//
//  ThemeEmitter.swift
//  Woodcase
//

/// Emits CSS custom property declarations from a ``ThemeManifest``.
public enum ThemeEmitter {
    /// Emit a `theme.css` file from the given theme manifest.
    public static func emitCSS(theme: ThemeManifest) -> GeneratedFile {
        emitCSS(theme: theme, customProperties: [])
    }

    /// Emit a `theme.css` file declaring the manifest's variables and the properties the
    /// emitter derived from them, each under the selector for its theme.
    ///
    /// - Parameters:
    ///   - theme: The document's theme manifest.
    ///   - customProperties: Computed per-theme values, such as baked mesh gradients.
    static func emitCSS(theme: ThemeManifest, customProperties: [ThemedCustomProperty]) -> GeneratedFile {
        var output = ""

        // Group all declarations by their conditions, formatted for CSS
        var groups: [ConditionKey: [(name: String, css: String)]] = [:]
        func declare(_ name: String, _ value: AnyCodable, _ type: PenVariableType, under conditions: [String: String]) {
            groups[ConditionKey(conditions: conditions), default: []].append((name, formatValue(value, type: type)))
        }

        for variable in theme.variables {
            if variable.isThemed {
                // First themed value goes to :root as default
                if let first = variable.values.first {
                    declare(variable.name, first.value, variable.type, under: [:])
                }
                // Remaining values go to their condition selectors
                for themedValue in variable.values.dropFirst() {
                    declare(variable.name, themedValue.value, variable.type, under: themedValue.conditions)
                }
            } else {
                // Simple variables go to :root
                for themedValue in variable.values {
                    declare(variable.name, themedValue.value, variable.type, under: [:])
                }
            }
        }

        // Computed properties arrive with finished CSS values
        for property in customProperties {
            for value in property.values {
                groups[ConditionKey(conditions: value.conditions), default: []].append((property.name, value.css))
            }
        }

        // Emit :root first, then conditional selectors sorted by name
        let rootKey = ConditionKey(conditions: [:])
        if let rootVars = groups[rootKey] {
            output += ":root {\n"
            for (name, css) in rootVars.sorted(by: { $0.name < $1.name }) {
                output += "  --\(name): \(css);\n"
            }
            output += "}\n"
        }

        // Emit conditional selectors
        let conditionalKeys = groups.keys
            .filter { !$0.conditions.isEmpty }
            .sorted { $0.selectorString < $1.selectorString }

        for key in conditionalKeys {
            guard let vars = groups[key] else { continue }
            output += "\n\(key.selectorString) {\n"
            for (name, css) in vars.sorted(by: { $0.name < $1.name }) {
                output += "  --\(name): \(css);\n"
            }
            output += "}\n"
        }

        return GeneratedFile(path: "theme.css", content: output)
    }

    // MARK: - Private

    private static func formatValue(_ value: AnyCodable, type: PenVariableType) -> String {
        let suffix = type == .number ? "px" : ""
        switch value {
        case let .string(s): return type == .string ? "'\(s)'" : s
        case let .int(n): return "\(n)\(suffix)"
        case let .double(d):
            if d == d.rounded(), !d.isInfinite {
                return "\(Int(d))\(suffix)"
            }
            return "\(d)\(suffix)"
        case let .bool(b): return b ? "1" : "0"
        default: return String(describing: value)
        }
    }
}

// MARK: - ConditionKey

extension ThemeEmitter {
    struct ConditionKey: Hashable {
        var conditions: [String: String]

        var selectorString: String {
            if conditions.isEmpty { return ":root" }
            return conditions.sorted { $0.key < $1.key }
                .map { "[data-\($0.key)=\"\($0.value)\"]" }
                .joined()
        }
    }
}
