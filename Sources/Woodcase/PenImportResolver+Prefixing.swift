//
//  PenImportResolver+Prefixing.swift
//  Woodcase
//
//  Created by Claude on 2026-03-24.
//

import Foundation

/// Handles alias-prefixing of node trees, variables, and themes for import resolution.
enum PenImportPrefixer {
    // MARK: - Node Prefixing

    /// Prefixes all identifiers in a node tree with the given alias.
    ///
    /// Transforms:
    /// - Node IDs: `"btnBase"` → `"V:btnBase"`
    /// - Ref targets: `"ref": "icon1"` → `"ref": "V:icon1"`
    /// - Descendant override keys (per `/`-separated segment)
    /// - Variable references (`$name` → `$V:name`)
    static func prefixNode(_ node: PenNode, alias: String) -> PenNode {
        var result = PenNode(
            id: "\(alias):\(node.id)",
            common: node.common,
            kind: prefixKind(node.kind, alias: alias),
            extras: node.extras
        )
        result.common = node.common
        return result
    }

    // MARK: - Kind Prefixing

    private static func prefixKind(_ kind: PenNode.Kind, alias: String) -> PenNode.Kind {
        switch kind {
        case let .frame(data):
            var updated = data
            updated.children = data.children?.map { prefixNode($0, alias: alias) }
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .frame(updated)
        case let .group(data):
            var updated = data
            updated.children = data.children?.map { prefixNode($0, alias: alias) }
            return .group(updated)
        case let .ref(data):
            var updated = data
            updated.ref = "\(alias):\(data.ref)"
            updated.descendants = prefixDescendantKeys(data.descendants, alias: alias)
            return .ref(updated)
        case let .text(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .text(updated)
        case let .rectangle(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .rectangle(updated)
        case let .ellipse(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .ellipse(updated)
        case let .path(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .path(updated)
        case let .line(data):
            var updated = data
            prefixStroke(&updated, alias: alias)
            return .line(updated)
        case let .polygon(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .polygon(updated)
        case let .icon(data):
            var updated = data
            updated.fills = prefixFills(data.fills, alias: alias)
            return .icon(updated)
        case let .script(data):
            var updated = data
            updated.inputs = data.inputs?.mapValues { prefixScriptInput($0, alias: alias) }
            if case let .variable(name) = data.clip {
                updated.clip = .variable("\(alias):\(name)")
            }
            return .script(updated)
        case let .browser(data):
            var updated = data
            prefixStroke(&updated, alias: alias)
            return .browser(updated)
        case let .connection(data):
            var updated = data
            updated.source.path = prefixPath(data.source.path, alias: alias)
            updated.target.path = prefixPath(data.target.path, alias: alias)
            prefixStroke(&updated, alias: alias)
            return .connection(updated)
        default:
            return kind
        }
    }

    private static func prefixScriptInput(_ input: PenScriptInput, alias: String) -> PenScriptInput {
        guard case let .variable(name) = input else { return input }
        return .variable("\(alias):\(name)")
    }

    // MARK: - Variable Prefixing

    /// Prefixes theme conditions within a variable's themed values.
    static func prefixVariable(_ variable: PenVariable, alias: String) -> PenVariable {
        var result = variable
        switch variable.value {
        case let .themed(themedValues):
            result.value = .themed(themedValues.map { themedValue in
                var updated = themedValue
                if let theme = themedValue.theme {
                    updated.theme = Dictionary(uniqueKeysWithValues: theme.map { axis, option in
                        ("\(alias):\(axis)", option)
                    })
                }
                // Prefix variable references in the value itself
                updated.value = prefixAnyCodableVarRefs(themedValue.value, alias: alias)
                return updated
            })
        case let .simple(value):
            result.value = .simple(prefixAnyCodableVarRefs(value, alias: alias))
        }
        return result
    }

    // MARK: - Descendant Key Prefixing

    /// Prefixes each segment of a slash-separated path of node ids — a connection's
    /// endpoint, which names a node the way a descendant override key does.
    private static func prefixPath(_ path: String, alias: String) -> String {
        path.split(separator: "/").map { "\(alias):\($0)" }.joined(separator: "/")
    }

    /// Prefixes each segment of slash-separated descendant override keys,
    /// and prefixes identifiers within override values (ref targets, node IDs,
    /// variable references, and nested children/descendants).
    private static func prefixDescendantKeys(
        _ descendants: [String: PenDescendantOverride]?,
        alias: String
    ) -> [String: PenDescendantOverride]? {
        guard let descendants else { return nil }
        return Dictionary(uniqueKeysWithValues: descendants.map { key, override in
            let prefixedKey = key.split(separator: "/").map { segment in
                "\(alias):\(segment)"
            }.joined(separator: "/")
            let prefixedOverride = PenDescendantOverride(
                properties: prefixOverrideProperties(override.properties, alias: alias)
            )
            return (prefixedKey, prefixedOverride)
        })
    }

    /// Prefixes identifiers within a descendant override's property dictionary.
    ///
    /// Handles:
    /// - `"ref"` values (component reference targets)
    /// - `"id"` values (node identifiers)
    /// - `"children"` arrays (recursively prefix each child node dict)
    /// - `"descendants"` dicts (prefix keys and recurse into values)
    /// - `$`-prefixed strings (variable references)
    private static func prefixOverrideProperties(
        _ properties: [String: AnyCodable],
        alias: String
    ) -> [String: AnyCodable] {
        var result = properties

        // Prefix ref target
        if case let .string(ref) = result["ref"] {
            result["ref"] = .string("\(alias):\(ref)")
        }

        // Prefix node ID
        if case let .string(id) = result["id"] {
            result["id"] = .string("\(alias):\(id)")
        }

        // Prefix children array (each child is a node property dict)
        if case let .array(children) = result["children"] {
            result["children"] = .array(children.map { child in
                guard case let .dictionary(childDict) = child else { return child }
                return .dictionary(prefixOverrideProperties(childDict, alias: alias))
            })
        }

        // Prefix descendants (keys and values)
        if case let .dictionary(descendants) = result["descendants"] {
            var prefixedDescendants: [String: AnyCodable] = [:]
            for (key, value) in descendants {
                let prefixedKey = key.split(separator: "/").map { segment in
                    "\(alias):\(segment)"
                }.joined(separator: "/")
                if case let .dictionary(overrideDict) = value {
                    prefixedDescendants[prefixedKey] = .dictionary(
                        prefixOverrideProperties(overrideDict, alias: alias)
                    )
                } else {
                    prefixedDescendants[prefixedKey] = value
                }
            }
            result["descendants"] = .dictionary(prefixedDescendants)
        }

        // Prefix $-prefixed variable references in string values
        for (key, value) in result {
            if case let .string(str) = value, str.hasPrefix("$"),
               key != "ref", key != "id"
            {
                let name = String(str.dropFirst())
                result[key] = .string("$\(alias):\(name)")
            }
        }

        return result
    }

    // MARK: - Variable Reference Prefixing in Values

    /// Prefixes `$`-prefixed variable references in fills.
    private static func prefixFills(_ fills: PenFills?, alias: String) -> PenFills? {
        guard let fills else { return nil }
        switch fills {
        case let .single(fill):
            return .single(prefixFill(fill, alias: alias))
        case let .multiple(fillArray):
            return .multiple(fillArray.map { prefixFill($0, alias: alias) })
        }
    }

    private static func prefixFill(_ fill: PenFill, alias: String) -> PenFill {
        switch fill {
        case let .shorthand(str) where str.hasPrefix("$"):
            let name = String(str.dropFirst())
            return .shorthand("$\(alias):\(name)")
        case let .color(colorFill):
            var result = colorFill
            result.color = prefixPenValue(colorFill.color, alias: alias)
            return .color(result)
        case let .gradient(gradFill):
            var result = gradFill
            result.colors = gradFill.colors?.map { stop in
                PenFill.PenGradientStop(
                    color: prefixPenValue(stop.color, alias: alias),
                    position: stop.position
                )
            }
            return .gradient(result)
        case let .shader(shaderFill):
            var result = shaderFill
            result.uniforms = shaderFill.uniforms?.mapValues { prefixShaderUniform($0, alias: alias) }
            return .shader(result)
        default:
            return fill
        }
    }

    private static func prefixShaderUniform(_ uniform: PenShaderUniform, alias: String) -> PenShaderUniform {
        guard case let .variable(name) = uniform else { return uniform }
        return .variable("\(alias):\(name)")
    }

    private static func prefixStroke(_ data: inout some PenStrokable, alias: String) {
        data.stroke = prefixFills(data.stroke, alias: alias)
    }

    /// Prefixes a PenValue's variable name if it's a `.variable` case.
    private static func prefixPenValue<T>(_ value: PenValue<T>?, alias: String) -> PenValue<T>? {
        guard let value else { return nil }
        switch value {
        case let .variable(name):
            return .variable("\(alias):\(name)")
        case .literal:
            return value
        }
    }

    private static func prefixPenValue<T>(_ value: PenValue<T>, alias: String) -> PenValue<T> {
        switch value {
        case let .variable(name):
            .variable("\(alias):\(name)")
        case .literal:
            value
        }
    }

    /// Prefixes `$`-prefixed string values in AnyCodable (for variable chains in variable values).
    private static func prefixAnyCodableVarRefs(_ value: AnyCodable, alias: String) -> AnyCodable {
        switch value {
        case let .string(str) where str.hasPrefix("$"):
            let name = String(str.dropFirst())
            return .string("$\(alias):\(name)")
        case let .dictionary(dict):
            return .dictionary(dict.mapValues { prefixAnyCodableVarRefs($0, alias: alias) })
        case let .array(arr):
            return .array(arr.map { prefixAnyCodableVarRefs($0, alias: alias) })
        default:
            return value
        }
    }

    // MARK: - PenSizing Variable Prefixing

    /// Prefixes variable references in sizing values.
    static func prefixSizing(_ sizing: PenSizing?, alias: String) -> PenSizing? {
        guard let sizing else { return nil }
        switch sizing {
        case let .variable(name):
            return .variable("\(alias):\(name)")
        default:
            return sizing
        }
    }
}
