//
//  PenImportedDefinitions.swift
//  Woodcase
//

import Foundation

/// What a document's imports contribute, prefixed and ready to use, kept apart from
/// the document's own tree.
///
/// ``PenImportResolver/resolve(_:libraries:)`` merges a library's components into the
/// host as extra root children, which is right for `generate` — every component becomes
/// code — and wrong for anything that shows the canvas: Pen never draws an imported
/// definition on the importing document's canvas, so `tree`, `lint`, `shot`, `render`
/// and the viewer must be able to *expand* an instance of `V:Button` without `V:Button`
/// itself becoming an artboard. This is the other shape of the same resolution: the
/// components go to the ref expander's registry (see ``expand(_:for:)``), and only the
/// variables and theme axes — which are tables, not tree — merge into the document.
public struct PenImportedDefinitions: Friendly {
    /// Each imported reusable node, prefixed, with its whole subtree, keyed by its
    /// prefixed id (`"V:Cmp01"`). Only a library's outermost reusables are entries; a
    /// reusable nested inside one travels inside its subtree.
    public var components: [String: PenNode]

    /// The libraries' variables, prefixed (`"V:accent"`).
    public var variables: [String: PenVariable]

    /// The libraries' theme axes, prefixed (`"V:mode"`).
    public var themes: [String: [String]]

    /// Creates a set of definitions.
    ///
    /// - Parameters:
    ///   - components: Prefixed reusable subtrees, keyed by prefixed id.
    ///   - variables: Prefixed variables.
    ///   - themes: Prefixed theme axes.
    public init(
        components: [String: PenNode] = [:],
        variables: [String: PenVariable] = [:],
        themes: [String: [String]] = [:]
    ) {
        self.components = components
        self.variables = variables
        self.themes = themes
    }

    /// Nothing imported.
    public static let none = PenImportedDefinitions()

    /// The document with the imported variables and theme axes merged in, the host's
    /// winning on a name both define. Its children and `imports` are left exactly as
    /// they were.
    ///
    /// - Parameter document: The host document.
    /// - Returns: The document, able to resolve `$V:name` and pin `V:axis`.
    public func merged(into document: PenDocument) -> PenDocument {
        guard !variables.isEmpty || !themes.isEmpty else { return document }
        var result = document
        let mergedVariables = (document.variables ?? [:]).merging(variables) { host, _ in host }
        let mergedThemes = (document.themes ?? [:]).merging(themes) { host, _ in host }
        result.variables = mergedVariables.isEmpty ? nil : mergedVariables
        result.themes = mergedThemes.isEmpty ? nil : mergedThemes
        return result
    }

    /// Every reusable the imports define — each entry of ``components`` and any
    /// reusable nested inside one — keyed by prefixed id: the registry a ref
    /// expansion adds to the document's own.
    public var registry: [String: PenNode] {
        PenRefExpander.buildRegistry(from: components.keys.sorted().compactMap { components[$0] })
    }

    /// Expands a document's refs with the imported components available, after merging
    /// in the imported variables and theme axes.
    ///
    /// - Parameters:
    ///   - document: The host document, as materialized.
    ///   - purpose: What the output is for; see ``PenRefExpander/Purpose``.
    /// - Returns: The expanded document. No imported definition is ever one of its roots.
    public func expand(_ document: PenDocument, for purpose: PenRefExpander.Purpose) -> PenDocument {
        PenRefExpander.expand(merged(into: document), for: purpose, imported: registry)
    }
}
