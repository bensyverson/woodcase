//
//  NodePropertyCodec+PropertyPaths.swift
//  Woodcase
//

import Foundation

/// The way back from a raw key to a property path, and the variable type a property
/// binds — the two lookups the inspector queries and the planner share.
extension NodePropertyCodec {
    /// Every `kind.*` path any node type takes.
    ///
    /// Field names are unique across kinds, so a raw key names at most one of them
    /// whatever the node's type.
    static let allKindPaths: Set<String> = PenNode.NodeType.allCases.reduce(into: []) {
        $0.formUnion(PropertyDiff.allKindKeys($1))
    }

    /// The property path a raw .pen key is stored for — the inverse of ``rawKey(for:)``.
    ///
    /// - Parameter key: A raw key, as a `descendants` entry or a ref's root overrides
    ///   spell it (`fill`).
    /// - Returns: `common.<field>` or `kind.<field>`, or `nil` for a key that is no
    ///   property of any type — `children`, `type`.
    static func path(forRawKey key: String) -> String? {
        let field = fieldName(forRawKey: key)
        let common = commonPrefix + field
        if commonPaths.contains(common) { return common }
        let kind = kindPrefix + field
        return allKindPaths.contains(kind) ? kind : nil
    }

    /// The field a property names, written as a path or as a raw key.
    ///
    /// - Parameter property: `kind.fills` or `fill`.
    /// - Returns: The field name the shape table is keyed by — `fills`.
    static func field(of property: String) -> String {
        fieldName(of: property) ?? fieldName(forRawKey: property)
    }

    /// The type a `$variable` bound to a property must have.
    ///
    /// - Parameter property: A property path or a raw key.
    /// - Returns: The type, or `nil` when the property takes no variable.
    static func bindableVariableType(of property: String) -> PenVariableType? {
        shape(of: field(of: property))?.variable
    }
}
