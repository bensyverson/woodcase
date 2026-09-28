//
//  PenVariableResolver.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Stateless variable resolver for .pen documents.
///
/// Walks the entire document tree replacing `PenValue.variable("name")` with
/// `PenValue.literal(resolvedValue)` by looking up each name in the document's
/// variable definitions (with theme matching and external overrides).
///
/// The resolver is pure: it returns a new ``PenDocument`` without mutating the input.
/// The variables dictionary is preserved on the output for downstream inspection.
///
/// ```swift
/// let resolved = PenVariableResolver.resolve(document, theme: ["mode": "dark"])
/// ```
///
/// ## Text content forgives a name nothing defines
///
/// A `$name` is a reference. One naming a variable the document defines **nowhere** —
/// in any theme — is, in text content alone, the literal it almost certainly was:
/// `$30.00` is a price, not a dangling reference to a variable called `30.00`, and it
/// is restored as the literal so it draws and `lint` stays quiet. The rule belongs to
/// the property, not to the verb that wrote it, so an instance's `descendants` override
/// of `content` gets it too — see `resolveAnyCodableValue`.
///
/// The rule stops exactly there. A name the document **does** define still resolves,
/// and still stands as an unresolved `$name` when nothing resolves it — a circular
/// chain, say — so forgiveness can never hide a genuine dangling reference. Every
/// other property is strict whatever it was written by. ``PenDollarEscape`` is the way
/// to say "literal" out loud, and the way to write one this rule would not forgive.
public enum PenVariableResolver {
    // MARK: - Public API

    /// Resolves all variable references in the document tree using inherited per-node theming.
    ///
    /// Themes cascade like CSS: children inherit the active theme from their parent.
    /// A node with `common.theme` overrides those axes for itself and its descendants.
    /// Nodes without `common.theme` use the inherited theme (defaulting to the first
    /// option per axis at the root).
    ///
    /// - Parameters:
    ///   - document: The parsed .pen document.
    ///   - overrides: External variable values that take precedence over
    ///     document-defined variables (e.g. runtime bindings from FPP).
    /// - Returns: A new document with variable references resolved to literals
    ///   where possible. Unresolvable references (missing, type mismatch, circular)
    ///   are left as `.variable`.
    public static func resolve(
        _ document: PenDocument,
        overrides: [String: AnyCodable] = [:]
    ) -> PenDocument {
        let variables = document.variables ?? [:]
        let definedNames = Set(variables.keys).union(overrides.keys)

        // Compute the default theme: first option per axis
        let rootTheme = Self.defaultTheme(from: document.themes)

        var result = document
        result.children = resolveTree(
            document.children,
            rootTheme: rootTheme,
            variables: variables,
            overrides: overrides,
            definedNames: definedNames
        )
        return result
    }

    /// Resolves all variable references using a specific theme at the root level.
    ///
    /// This is a convenience for callers (like the CLI `--theme` pin) that want to
    /// force a specific root theme. Per-node theme inheritance still applies —
    /// children with their own `common.theme` still override.
    ///
    /// - Parameters:
    ///   - document: The parsed .pen document.
    ///   - theme: Active theme axes (e.g. `["mode": "dark"]`). Merged into the
    ///     default theme (first option per axis) to form the root effective theme.
    ///   - overrides: External variable values that take precedence over
    ///     document-defined variables.
    /// - Returns: A new document with variable references resolved to literals
    ///   where possible.
    public static func resolve(
        _ document: PenDocument,
        theme: [String: String],
        overrides: [String: AnyCodable] = [:]
    ) -> PenDocument {
        let variables = document.variables ?? [:]
        let definedNames = Set(variables.keys).union(overrides.keys)

        // Start with the default, then overlay the pin
        var rootTheme = defaultTheme(from: document.themes)
        for (axis, value) in theme {
            rootTheme[axis] = value
        }

        var result = document
        result.children = resolveTree(
            document.children,
            rootTheme: rootTheme,
            variables: variables,
            overrides: overrides,
            definedNames: definedNames
        )
        return result
    }

    // MARK: - Theme Helpers

    /// Computes the default theme: first option per axis.
    private static func defaultTheme(from themes: [String: [String]]?) -> [String: String] {
        guard let themes else { return [:] }
        var result: [String: String] = [:]
        for (axis, options) in themes {
            if let first = options.first {
                result[axis] = first
            }
        }
        return result
    }

    /// A stable cache key for a theme dictionary.
    private static func cacheKey(for theme: [String: String]) -> String {
        theme.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    // MARK: - Inherited Theme Tree Walk

    /// Resolves every node in a forest, each against the theme it inherits.
    ///
    /// The walk is ``PenTreeRewrite``'s, top-down from a work list, with the inherited
    /// theme as the context each node hands its children: resolving a deep tree
    /// recursively cost about 11 KB of stack a level in a debug build and overflowed a
    /// Swift task's (`project/2026-09-26-debug-stack-depth.md`).
    ///
    /// - Parameters:
    ///   - roots: The top-level nodes, with their subtrees.
    ///   - rootTheme: The theme the roots inherit.
    ///   - variables: The document's variables.
    ///   - overrides: External values that take precedence over the document's.
    ///   - definedNames: Every variable name the document or the overrides define.
    /// - Returns: The forest with every node's references resolved.
    private static func resolveTree(
        _ roots: [PenNode],
        rootTheme: [String: String],
        variables: [String: PenVariable],
        overrides: [String: AnyCodable],
        definedNames: Set<String>
    ) -> [PenNode] {
        // Cache variable tables keyed by effective theme (typically 2-4 combos)
        var tableCache: [String: [String: AnyCodable]] = [:]

        return PenTreeRewrite.rewrite(roots, context: rootTheme) { node, inheritedTheme in
            // A node's own theme overrides the axes it names, for itself and below.
            var effectiveTheme = inheritedTheme
            for (axis, value) in node.common.theme ?? [:] {
                effectiveTheme[axis] = value
            }

            let key = cacheKey(for: effectiveTheme)
            let table: [String: AnyCodable]
            if let cached = tableCache[key] {
                table = cached
            } else {
                table = buildTable(from: variables, theme: effectiveTheme, overrides: overrides)
                tableCache[key] = table
            }

            var result = node
            result.common = resolveCommon(node.common, from: table)
            result.kind = resolveKind(node.kind, from: table, definedNames: definedNames)
            return .descend(result, effectiveTheme)
        }
    }

    // MARK: - Variable Table

    /// Every variable's value under `theme`: a themed value's specific match (the last one
    /// wins) before its unconditional default, `overrides` over both, and chains of
    /// `$name` references followed to their end; a variable in a cycle is left out.
    ///
    /// Internal so code generation reads a variable under each theme exactly as the
    /// renderer does (`SwiftUITheme`).
    static func buildTable(
        from variables: [String: PenVariable],
        theme: [String: String],
        overrides: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        var table: [String: AnyCodable] = [:]

        // Phase 1: Resolve document variables (with theme matching)
        for (name, variable) in variables {
            switch variable.value {
            case let .simple(value):
                table[name] = value
            case let .themed(themedValues):
                // Specific matches (non-nil theme) take priority over defaults (nil theme).
                // Among specific matches, last match wins. Default is fallback only.
                // If no default and no specific match, use the first value as fallback
                // (Pen treats the first themed variant as the default when no theme is active).
                var defaultValue: AnyCodable?
                var specificValue: AnyCodable?
                for themedValue in themedValues {
                    if themedValue.theme == nil {
                        defaultValue = themedValue.value
                    } else if matches(themed: themedValue, activeTheme: theme) {
                        specificValue = themedValue.value
                    }
                }
                if let value = specificValue ?? defaultValue ?? themedValues.first?.value {
                    table[name] = value
                }
            }
        }

        // Phase 2: Apply external overrides (precedence over document variables)
        for (name, value) in overrides {
            table[name] = value
        }

        // Phase 3: Resolve variable chains
        resolveChains(&table)

        return table
    }

    private static func matches(themed: PenThemedValue, activeTheme: [String: String]) -> Bool {
        guard let conditions = themed.theme else {
            // nil theme = default, always matches
            return true
        }
        // All conditions must be satisfied (subset check)
        for (axis, option) in conditions {
            if activeTheme[axis] != option {
                return false
            }
        }
        return true
    }

    private static func resolveChains(_ table: inout [String: AnyCodable]) {
        let maxDepth = 10

        // First pass: identify all keys involved in circular chains
        var cyclicKeys: Set<String> = []
        for key in table.keys {
            var current = key
            var visited: [String] = [current]
            var depth = 0

            while depth < maxDepth {
                guard case let .string(ref) = table[current], ref.hasPrefix("$") else {
                    break
                }
                let target = String(ref.dropFirst())
                if let cycleStart = visited.firstIndex(of: target) {
                    // All keys from cycleStart onward are in the cycle
                    cyclicKeys.formUnion(visited[cycleStart...])
                    break
                }
                visited.append(target)
                current = target
                depth += 1
            }
        }

        // Remove all cyclic keys
        for key in cyclicKeys {
            table.removeValue(forKey: key)
        }

        // Second pass: resolve remaining chains to their terminal values
        for key in Array(table.keys) {
            var current = key
            var visited: Set<String> = [current]
            var depth = 0

            while depth < maxDepth {
                guard case let .string(ref) = table[current], ref.hasPrefix("$") else {
                    break
                }
                let target = String(ref.dropFirst())
                if visited.contains(target) || table[target] == nil {
                    break
                }
                visited.insert(target)
                current = target
                depth += 1
            }

            if current != key, let resolved = table[current] {
                table[key] = resolved
            }
        }
    }

    // MARK: - Core Resolve Primitive

    private static func resolve<T>(_ value: PenValue<T>, from table: [String: AnyCodable]) -> PenValue<T> {
        guard let name = value.variableName else {
            return value
        }
        guard let raw = table[name] else {
            return value
        }
        if let extracted: T = extract(raw) {
            return .literal(extracted)
        }
        return value
    }

    private static func resolve<T>(_ value: PenValue<T>?, from table: [String: AnyCodable]) -> PenValue<T>? {
        value.map { resolve($0, from: table) }
    }

    /// Extracts a concrete Swift type from an AnyCodable value.
    private static func extract<T>(_ value: AnyCodable) -> T? {
        switch value {
        case let .string(s) where T.self == String.self:
            s as? T
        case let .bool(b) where T.self == Bool.self:
            b as? T
        case let .double(d) where T.self == Double.self:
            d as? T
        case let .int(i) where T.self == Double.self:
            Double(i) as? T
        default:
            nil
        }
    }

    // MARK: - One Node

    private static func resolveCommon(
        _ common: PenNodeCommon,
        from table: [String: AnyCodable]
    ) -> PenNodeCommon {
        var result = common
        result.x = resolve(common.x, from: table)
        result.y = resolve(common.y, from: table)
        result.rotation = resolve(common.rotation, from: table)
        result.opacity = resolve(common.opacity, from: table)
        result.enabled = resolve(common.enabled, from: table)
        result.flipX = resolve(common.flipX, from: table)
        result.flipY = resolve(common.flipY, from: table)
        return result
    }

    private static func resolveKind(
        _ kind: PenNode.Kind,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.Kind {
        switch kind {
        case let .frame(data):
            .frame(resolveFrameData(data, from: table))
        case let .text(data):
            .text(resolveTextData(data, from: table, definedNames: definedNames))
        case let .rectangle(data):
            .rectangle(resolveRectangleData(data, from: table))
        case let .ellipse(data):
            .ellipse(resolveEllipseData(data, from: table))
        case let .path(data):
            .path(resolvePathData(data, from: table))
        case let .group(data):
            .group(resolveGroupData(data, from: table))
        case let .line(data):
            .line(resolveLineData(data, from: table))
        case let .polygon(data):
            .polygon(resolvePolygonData(data, from: table))
        case let .note(data):
            .note(resolveNoteData(data, from: table, definedNames: definedNames))
        case let .prompt(data):
            .prompt(resolvePromptData(data, from: table, definedNames: definedNames))
        case let .context(data):
            .context(resolveContextData(data, from: table, definedNames: definedNames))
        case let .icon(data):
            .icon(resolveIconData(data, from: table))
        case let .script(data):
            .script(resolveScriptData(data, from: table))
        case let .browser(data):
            .browser(resolveBrowserData(data, from: table))
        case let .connection(data):
            .connection(resolveConnectionData(data, from: table))
        case let .ref(data):
            .ref(resolveRefData(data, from: table, definedNames: definedNames))
        case .unknown:
            kind
        }
    }

    private static func resolveRefData(
        _ data: PenNode.RefData,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.RefData {
        var result = data
        if let descendants = data.descendants {
            result.descendants = descendants.mapValues { override in
                PenDescendantOverride(
                    properties: resolveOverrideProperties(
                        override.properties, from: table, definedNames: definedNames
                    )
                )
            }
        }
        if let rootOverrides = data.rootOverrides {
            result.rootOverrides = resolveOverrideProperties(
                rootOverrides, from: table, definedNames: definedNames
            )
        }
        return result
    }

    /// The raw .pen keys that hold a node's text, and so forgive a `$name` the document
    /// defines nowhere.
    ///
    /// An override map is keyed by the raw name the merge reads — `content`, not
    /// `kind.content` — and the forgiveness is the *property's* rule, not the verb's:
    /// see ``resolveTextContent(_:from:definedNames:)``, which applies it to a text
    /// node's own content.
    private static let forgivingOverrideKeys: Set<String> = ["content"]

    /// Resolves `$`-prefixed variable references in descendant override properties.
    ///
    /// Override properties are raw `[String: AnyCodable]` dictionaries. Any string
    /// value starting with `$` is treated as a variable reference and resolved from
    /// the table if possible.
    private static func resolveOverrideProperties(
        _ properties: [String: AnyCodable],
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> [String: AnyCodable] {
        properties.reduce(into: [:]) { result, entry in
            result[entry.key] = resolveAnyCodableValue(
                entry.value, key: entry.key, from: table, definedNames: definedNames
            )
        }
    }

    /// Resolves one override value, carrying the key it is stored under so a `content`
    /// gets the same forgiveness a text node's own content gets.
    ///
    /// - Parameters:
    ///   - value: The value as the override map stores it.
    ///   - key: The raw .pen key it is stored under.
    ///   - table: The variable table for the active theme.
    ///   - definedNames: Every variable name the document defines, in any theme.
    /// - Returns: The resolved value; the value itself when nothing resolves it; or, for
    ///   a `content` naming no variable at all, the same string written back escaped —
    ///   the wire form of the literal it almost certainly was.
    private static func resolveAnyCodableValue(
        _ value: AnyCodable,
        key: String,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> AnyCodable {
        switch value {
        case let .string(str) where str.hasPrefix(PenDollarEscape.dollar):
            let name = String(str.dropFirst())
            if let resolved = table[name] {
                return resolved
            }
            if forgivingOverrideKeys.contains(key), !definedNames.contains(name) {
                return .string(PenDollarEscape.escaped(str))
            }
            return value
        case let .dictionary(dict):
            return .dictionary(dict.reduce(into: [:]) { result, entry in
                result[entry.key] = resolveAnyCodableValue(
                    entry.value, key: entry.key, from: table, definedNames: definedNames
                )
            })
        case let .array(arr):
            return .array(arr.map {
                resolveAnyCodableValue($0, key: key, from: table, definedNames: definedNames)
            })
        default:
            return value
        }
    }

    // MARK: - Kind-Specific Resolvers

    /// A frame's own properties; its children are the walk's, not this function's.
    private static func resolveFrameData(
        _ data: PenNode.FrameData,
        from table: [String: AnyCodable]
    ) -> PenNode.FrameData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.cornerRadius = resolveCornerRadius(data.cornerRadius, from: table)
        result.clip = resolve(data.clip, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        result.gap = resolve(data.gap, from: table)
        result.padding = resolvePadding(data.padding, from: table)
        return result
    }

    private static func resolveTextData(
        _ data: PenNode.TextData,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.TextData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.content = resolveTextContent(data.content, from: table, definedNames: definedNames)
        result.fontFamily = resolve(data.fontFamily, from: table)
        result.fontSize = resolve(data.fontSize, from: table)
        result.fontWeight = resolve(data.fontWeight, from: table)
        result.fontStyle = resolve(data.fontStyle, from: table)
        result.letterSpacing = resolve(data.letterSpacing, from: table)
        result.lineHeight = resolve(data.lineHeight, from: table)
        result.underline = resolve(data.underline, from: table)
        result.strikethrough = resolve(data.strikethrough, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveRectangleData(
        _ data: PenNode.RectangleData,
        from table: [String: AnyCodable]
    ) -> PenNode.RectangleData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.cornerRadius = resolveCornerRadius(data.cornerRadius, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveConnectionData(
        _ data: PenNode.ConnectionData,
        from table: [String: AnyCodable]
    ) -> PenNode.ConnectionData {
        var result = data
        resolveStroke(&result, from: table)
        return result
    }

    private static func resolveBrowserData(
        _ data: PenNode.BrowserData,
        from table: [String: AnyCodable]
    ) -> PenNode.BrowserData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.cornerRadius = resolveCornerRadius(data.cornerRadius, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveEllipseData(
        _ data: PenNode.EllipseData,
        from table: [String: AnyCodable]
    ) -> PenNode.EllipseData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.innerRadius = resolve(data.innerRadius, from: table)
        result.startAngle = resolve(data.startAngle, from: table)
        result.sweepAngle = resolve(data.sweepAngle, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolvePathData(
        _ data: PenNode.PathData,
        from table: [String: AnyCodable]
    ) -> PenNode.PathData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    /// A group's own properties; its children are the walk's, not this function's.
    private static func resolveGroupData(
        _ data: PenNode.GroupData,
        from table: [String: AnyCodable]
    ) -> PenNode.GroupData {
        var result = data
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveLineData(
        _ data: PenNode.LineData,
        from table: [String: AnyCodable]
    ) -> PenNode.LineData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolvePolygonData(
        _ data: PenNode.PolygonData,
        from table: [String: AnyCodable]
    ) -> PenNode.PolygonData {
        var result = data
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.polygonCount = resolve(data.polygonCount, from: table)
        result.cornerRadius = resolveCornerRadius(data.cornerRadius, from: table)
        result.fills = resolveFills(data.fills, from: table)
        resolveStroke(&result, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveNoteData(
        _ data: PenNode.NoteData,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.NoteData {
        var result = data
        result.content = resolveTextContent(data.content, from: table, definedNames: definedNames)
        return result
    }

    private static func resolvePromptData(
        _ data: PenNode.PromptData,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.PromptData {
        var result = data
        result.content = resolveTextContent(data.content, from: table, definedNames: definedNames)
        return result
    }

    private static func resolveContextData(
        _ data: PenNode.ContextData,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenNode.ContextData {
        var result = data
        result.content = resolveTextContent(data.content, from: table, definedNames: definedNames)
        return result
    }

    private static func resolveIconData(
        _ data: PenNode.IconData,
        from table: [String: AnyCodable]
    ) -> PenNode.IconData {
        var result = data
        result.icon = resolve(data.icon, from: table)
        result.library = resolve(data.library, from: table)
        result.weight = resolve(data.weight, from: table)
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.fills = resolveFills(data.fills, from: table)
        result.effects = resolveEffects(data.effects, from: table)
        return result
    }

    private static func resolveScriptData(
        _ data: PenNode.ScriptData,
        from table: [String: AnyCodable]
    ) -> PenNode.ScriptData {
        var result = data
        result.clip = resolve(data.clip, from: table)
        result.width = resolveSizing(data.width, from: table)
        result.height = resolveSizing(data.height, from: table)
        result.inputs = data.inputs?.mapValues { resolveScriptInput($0, from: table) }
        return result
    }

    private static func resolveScriptInput(
        _ input: PenScriptInput,
        from table: [String: AnyCodable]
    ) -> PenScriptInput {
        guard case let .variable(name) = input, let raw = table[name] else { return input }
        switch raw {
        case let .double(d): return .number(d)
        case let .int(i): return .number(Double(i))
        case let .bool(b): return .bool(b)
        case let .string(s): return .string(s)
        default: return input
        }
    }

    // MARK: - Compound Type Resolvers

    private static func resolveSizing(
        _ sizing: PenSizing?,
        from table: [String: AnyCodable]
    ) -> PenSizing? {
        guard let sizing else { return nil }
        switch sizing {
        case let .variable(name):
            guard let raw = table[name] else { return sizing }
            switch raw {
            case let .double(d):
                return .fixed(d)
            case let .int(i):
                return .fixed(Double(i))
            default:
                return sizing
            }
        default:
            return sizing
        }
    }

    private static func resolvePadding(
        _ padding: PenPadding?,
        from table: [String: AnyCodable]
    ) -> PenPadding? {
        guard let padding else { return nil }
        switch padding {
        case let .uniform(value):
            return .uniform(resolve(value, from: table))
        case let .symmetric(h, v):
            return .symmetric(h: resolve(h, from: table), v: resolve(v, from: table))
        case let .individual(top, right, bottom, left):
            return .individual(
                top: resolve(top, from: table),
                right: resolve(right, from: table),
                bottom: resolve(bottom, from: table),
                left: resolve(left, from: table)
            )
        }
    }

    private static func resolveCornerRadius(
        _ cornerRadius: PenCornerRadius?,
        from table: [String: AnyCodable]
    ) -> PenCornerRadius? {
        guard let cornerRadius else { return nil }
        switch cornerRadius {
        case let .uniform(value):
            return .uniform(resolve(value, from: table))
        case let .perCorner(tl, tr, br, bl):
            return .perCorner(
                topLeft: resolve(tl, from: table),
                topRight: resolve(tr, from: table),
                bottomRight: resolve(br, from: table),
                bottomLeft: resolve(bl, from: table)
            )
        }
    }

    private static func resolveFills(
        _ fills: PenFills?,
        from table: [String: AnyCodable]
    ) -> PenFills? {
        guard let fills else { return nil }
        switch fills {
        case let .single(fill):
            return .single(resolveFill(fill, from: table))
        case let .multiple(fillArray):
            return .multiple(fillArray.map { resolveFill($0, from: table) })
        }
    }

    private static func resolveFill(
        _ fill: PenFill,
        from table: [String: AnyCodable]
    ) -> PenFill {
        switch fill {
        case let .shorthand(str):
            if str.hasPrefix("$") {
                let name = String(str.dropFirst())
                if let raw = table[name], case let .string(resolved) = raw {
                    return .shorthand(resolved)
                }
            }
            return fill

        case let .color(colorFill):
            var result = colorFill
            result.color = resolve(colorFill.color, from: table)
            result.enabled = resolve(colorFill.enabled, from: table)
            return .color(result)

        case let .gradient(gradFill):
            var result = gradFill
            result.enabled = resolve(gradFill.enabled, from: table)
            result.opacity = resolve(gradFill.opacity, from: table)
            result.rotation = resolve(gradFill.rotation, from: table)
            result.colors = gradFill.colors?.map { stop in
                PenFill.PenGradientStop(
                    color: resolve(stop.color, from: table),
                    position: resolve(stop.position, from: table)
                )
            }
            result.size = resolveFillSize(gradFill.size, from: table)
            return .gradient(result)

        case let .image(imgFill):
            var result = imgFill
            result.enabled = resolve(imgFill.enabled, from: table)
            result.opacity = resolve(imgFill.opacity, from: table)
            return .image(result)

        case let .meshGradient(meshFill):
            var result = meshFill
            result.enabled = resolve(meshFill.enabled, from: table)
            result.opacity = resolve(meshFill.opacity, from: table)
            result.colors = meshFill.colors?.map { resolve($0, from: table) }
            return .meshGradient(result)

        case let .shader(shaderFill):
            var result = shaderFill
            result.enabled = resolve(shaderFill.enabled, from: table)
            result.opacity = resolve(shaderFill.opacity, from: table)
            result.uniforms = shaderFill.uniforms?.mapValues { resolveShaderUniform($0, from: table) }
            return .shader(result)

        case .unknown:
            return fill
        }
    }

    private static func resolveShaderUniform(
        _ uniform: PenShaderUniform,
        from table: [String: AnyCodable]
    ) -> PenShaderUniform {
        guard case let .variable(name) = uniform, let raw = table[name] else { return uniform }
        switch raw {
        case let .double(d): return .number(d)
        case let .int(i): return .number(Double(i))
        case let .bool(b): return .bool(b)
        case let .string(s): return .color(s)
        case let .array(arr):
            let doubles: [Double] = arr.compactMap {
                if case let .double(d) = $0 { return d }
                if case let .int(i) = $0 { return Double(i) }
                return nil
            }
            guard doubles.count == arr.count, (2 ... 4).contains(doubles.count) else { return uniform }
            return .vector(doubles)
        default: return uniform
        }
    }

    private static func resolveFillSize(
        _ size: PenFill.PenFillSize?,
        from table: [String: AnyCodable]
    ) -> PenFill.PenFillSize? {
        guard let size else { return nil }
        var result = size
        result.width = resolve(size.width, from: table)
        result.height = resolve(size.height, from: table)
        return result
    }

    private static func resolveStroke(
        _ data: inout some PenStrokable,
        from table: [String: AnyCodable]
    ) {
        data.stroke = resolveFills(data.stroke, from: table)
        data.strokeWidth = resolveStrokeWidth(data.strokeWidth, from: table)
    }

    private static func resolveStrokeWidth(
        _ width: PenStrokeWidth?,
        from table: [String: AnyCodable]
    ) -> PenStrokeWidth? {
        guard let width else { return nil }
        switch width {
        case let .uniform(value):
            return .uniform(resolve(value, from: table))
        case let .perSide(sides):
            return .perSide(PenStrokeWidth.Sides(
                top: resolve(sides.top, from: table),
                right: resolve(sides.right, from: table),
                bottom: resolve(sides.bottom, from: table),
                left: resolve(sides.left, from: table),
                extras: sides.extras
            ))
        }
    }

    private static func resolveEffects(
        _ effects: PenEffects?,
        from table: [String: AnyCodable]
    ) -> PenEffects? {
        guard let effects else { return nil }
        switch effects {
        case let .single(effect):
            return .single(resolveEffect(effect, from: table))
        case let .multiple(effectArray):
            return .multiple(effectArray.map { resolveEffect($0, from: table) })
        }
    }

    private static func resolveEffect(
        _ effect: PenEffect,
        from table: [String: AnyCodable]
    ) -> PenEffect {
        switch effect {
        case let .blur(blur):
            var result = blur
            result.enabled = resolve(blur.enabled, from: table)
            result.radius = resolve(blur.radius, from: table)
            return .blur(result)

        case let .backgroundBlur(bgBlur):
            var result = bgBlur
            result.enabled = resolve(bgBlur.enabled, from: table)
            result.radius = resolve(bgBlur.radius, from: table)
            return .backgroundBlur(result)

        case let .shadow(shadow):
            var result = shadow
            result.enabled = resolve(shadow.enabled, from: table)
            result.blur = resolve(shadow.blur, from: table)
            result.color = resolve(shadow.color, from: table)
            if let offset = shadow.offset {
                result.offset = PenEffect.PenOffset(
                    x: resolve(offset.x, from: table),
                    y: resolve(offset.y, from: table)
                )
            }
            return .shadow(result)

        case .unknown:
            return effect
        }
    }

    /// A text node's content, resolved, with a name nothing defines restored as the
    /// literal it almost certainly was.
    ///
    /// - Parameters:
    ///   - content: The content as the file stores it.
    ///   - table: The variable table for the active theme.
    ///   - definedNames: Every variable name the document defines, in any theme.
    /// - Returns: The resolved content, or the literal `$name` when the document
    ///   defines no variable of that name at all.
    private static func resolveTextContent(
        _ content: PenValue<String>?,
        from table: [String: AnyCodable],
        definedNames: Set<String>
    ) -> PenValue<String>? {
        guard let content else { return nil }
        let resolved = resolve(content, from: table)
        // If the resolved value is still a variable reference and the name was never
        // defined as a variable in the document, the text was likely a literal that
        // happened to start with "$" (e.g. "$186" for a price). Restore it as a
        // literal with the "$" prefix. If the name IS a defined variable (but couldn't
        // be resolved, e.g. circular chain), leave it as a variable reference — this
        // must never become a way to hide a genuine dangling reference.
        if let name = resolved.variableName, !definedNames.contains(name) {
            return .literal(PenDollarEscape.dollar + name)
        }
        return resolved
    }
}
