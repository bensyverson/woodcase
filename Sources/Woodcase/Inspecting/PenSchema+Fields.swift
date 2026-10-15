//
//  PenSchema+Fields.swift
//  Woodcase
//

import Foundation

/// The editable fields of a node type, for an inspector that builds its controls from
/// the schema rather than from a copy of the format.
///
/// Each row is a ``PenSchemaTable/Property`` — the same row `woodcase schema` prints — so
/// a control reads the path it writes, the ``PenSchemaTable/Property/spellings`` a picker
/// offers, the ``PenSchemaTable/Property/constraint`` a number field keeps to, the
/// ``PenSchemaTable/Property/variable`` type ``EditableDocument/bindableVariables(for:at:)``
/// lists, and the ``PenSchemaTable/Property/nested`` tables of a fill, an effect or a
/// stroke.
public extension PenSchema {
    /// Every property a node of one type takes: the `common.*` rows and its own `kind.*`
    /// rows in one list.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The rows, sorted by path.
    static func fields(for type: PenNode.NodeType) -> [PenSchemaTable.Property] {
        (common.properties + table(for: type).properties).sorted { $0.path < $1.path }
    }

    /// One property of a node type.
    ///
    /// - Parameters:
    ///   - property: A property path (`kind.fills`), a raw key (`fill`), or the path of a
    ///     `metadata.woodcase` key the type takes as a field (``woodcaseFields(for:)``).
    ///   - type: The node type.
    /// - Returns: The row, or `nil` when nodes of `type` do not take the property.
    static func field(_ property: String, for type: PenNode.NodeType) -> PenSchemaTable.Property? {
        if let row = woodcaseFields(for: type).first(where: { $0.path == property }) { return row }
        let path = NodePropertyCodec.fieldName(of: property) != nil
            ? property
            : NodePropertyCodec.path(forRawKey: property)
        guard let path else { return nil }
        if NodePropertyCodec.commonPaths.contains(path) {
            return common.properties.first { $0.path == path }
        }
        guard PropertyDiff.allKindKeys(type).contains(path) else { return nil }
        return table(for: type).properties.first { $0.path == path }
    }
}
