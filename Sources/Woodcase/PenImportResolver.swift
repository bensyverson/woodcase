//
//  PenImportResolver.swift
//  Woodcase
//
//  Created by Claude on 2026-03-24.
//

import Foundation

/// Stateless import resolver for .pen documents.
///
/// Resolves cross-file imports by prefixing library components, variables, and themes
/// with their import alias (e.g., `V:componentId`, `$V:--variable`, `V:ThemeAxis`).
/// It resolves one level, as Pen does: a library's own `imports` are never followed.
///
/// There are two shapes of the answer. ``definitions(for:libraries:)`` keeps the
/// imported components apart from the host's tree, for the ref expander's registry —
/// the shape every canvas read uses, through ``EditableDocument/expanded(for:)``, since
/// Pen never draws an imported definition on the importing canvas. ``resolve(_:libraries:)``
/// merges them into the tree as extra roots — the shape `generate` wants, where every
/// component becomes code.
///
/// ```swift
/// let resolved = PenImportResolver.resolve(document, libraries: ["libs/lib.pen": libDoc])
/// ```
public enum PenImportResolver {
    // MARK: - Public API

    /// Resolves imports using pre-loaded library documents.
    ///
    /// - Parameters:
    ///   - document: The parsed .pen document with optional `imports`.
    ///   - libraries: A dictionary mapping import paths (e.g., `"kit.lib.pen"`)
    ///     to their parsed ``PenDocument`` values.
    /// - Returns: A new document with library components appended as root children,
    ///   variables and themes merged in (the host winning on a name both define), all
    ///   under their alias prefixes, and the `imports` field cleared.
    public static func resolve(
        _ document: PenDocument,
        libraries: [String: PenDocument]
    ) -> PenDocument {
        guard let imports = document.imports, !imports.isEmpty else {
            return document
        }
        let definitions = definitions(for: imports, libraries: libraries)

        var result = definitions.merged(into: document)
        for alias in imports.keys.sorted() {
            guard let path = imports[alias], let library = libraries[path] else { continue }
            result.children += extractReusables(from: library.children).compactMap { component in
                definitions.components["\(alias):\(component.id)"]
            }
        }
        result.imports = nil
        return result
    }

    /// Resolves imports using a resolver closure for lazy or remote loading.
    ///
    /// - Parameters:
    ///   - document: The parsed .pen document with optional `imports`.
    ///   - resolver: A closure that takes an import path and returns the parsed document.
    /// - Returns: A new document with library components, variables, and themes merged in
    ///   under their alias prefixes, and the `imports` field cleared.
    public static func resolve(
        _ document: PenDocument,
        resolver: (String) throws -> PenDocument
    ) throws -> PenDocument {
        guard let imports = document.imports, !imports.isEmpty else {
            return document
        }

        var libraries: [String: PenDocument] = [:]
        for (_, path) in imports {
            if libraries[path] == nil {
                libraries[path] = try resolver(path)
            }
        }

        return resolve(document, libraries: libraries)
    }

    /// The prefixed components, variables and theme axes a document's imports
    /// contribute, without merging any of them into its tree.
    ///
    /// One level only, as in Pen: a library's own `imports` are not followed, so a
    /// component of the library that reaches through one names nothing. See
    /// ``PenLibraries`` for where the libraries come from.
    ///
    /// - Parameters:
    ///   - imports: The document's `imports` table, alias to path.
    ///   - libraries: The libraries, keyed by import path as written.
    /// - Returns: The definitions. An alias whose library is missing contributes nothing.
    public static func definitions(
        for imports: [String: String]?,
        libraries: [String: PenDocument]
    ) -> PenImportedDefinitions {
        var definitions = PenImportedDefinitions()
        for alias in (imports ?? [:]).keys.sorted() {
            guard let path = imports?[alias], let library = libraries[path] else { continue }

            for component in extractReusables(from: library.children) {
                let prefixed = PenImportPrefixer.prefixNode(component, alias: alias)
                definitions.components[prefixed.id] = prefixed
            }
            for (name, variable) in library.variables ?? [:] {
                definitions.variables["\(alias):\(name)"] = PenImportPrefixer.prefixVariable(variable, alias: alias)
            }
            for (axis, options) in library.themes ?? [:] {
                definitions.themes["\(alias):\(axis)"] = options
            }
        }
        return definitions
    }

    // MARK: - Helpers

    /// Recursively extracts all nodes with `reusable: true` from the tree.
    ///
    /// When a node is `reusable: true`, it is extracted as a whole (including its
    /// nested children). We do NOT recurse into an already-extracted reusable's
    /// children, because those nested reusables are already part of the parent's
    /// subtree and would create duplicate IDs after prefixing.
    private static func extractReusables(from nodes: [PenNode]) -> [PenNode] {
        var result: [PenNode] = []
        for node in nodes {
            if node.common.reusable == true {
                result.append(node)
            } else if let children = nodeChildren(node) {
                result.append(contentsOf: extractReusables(from: children))
            }
        }
        return result
    }

    /// Returns the children of a node, if it has any.
    private static func nodeChildren(_ node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }
}
