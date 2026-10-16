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
        fieldIndexes[type]?.fields ?? FieldIndex(type: type).fields
    }

    /// One property of a node type.
    ///
    /// A lookup in a table built once per type, so it costs a dictionary read.
    ///
    /// - Parameters:
    ///   - property: A property path (`kind.fills`), a raw key (`fill`), or the path of a
    ///     `metadata.woodcase` key the type takes as a field (``woodcaseFields(for:)``).
    ///   - type: The node type.
    /// - Returns: The row, or `nil` when nodes of `type` do not take the property.
    static func field(_ property: String, for type: PenNode.NodeType) -> PenSchemaTable.Property? {
        let index = fieldIndexes[type] ?? FieldIndex(type: type)
        if let row = index.woodcase[property] { return row }
        let path = NodePropertyCodec.fieldName(of: property) != nil
            ? property
            : NodePropertyCodec.path(forRawKey: property)
        guard let path else { return nil }
        return index.byPath[path]
    }
}

extension PenSchema {
    /// One type's rows, sorted and keyed by path, built once.
    struct FieldIndex: Friendly {
        /// The `common.*` rows and the type's own `kind.*` rows, sorted by path.
        let fields: [PenSchemaTable.Property]
        /// The same rows by path.
        let byPath: [String: PenSchemaTable.Property]
        /// The type's `metadata.woodcase` rows by path, which win over the others.
        let woodcase: [String: PenSchemaTable.Property]

        /// Indexes one type's rows.
        ///
        /// - Parameter type: The node type.
        init(type: PenNode.NodeType) {
            fields = (PenSchema.common.properties + PenSchema.table(for: type).properties).sorted { $0.path < $1.path }
            byPath = Dictionary(fields.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            woodcase = Dictionary(
                PenSchema.woodcaseFields(for: type).map { ($0.path, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    /// Every type's index, built once.
    static let fieldIndexes: [PenNode.NodeType: FieldIndex] = Dictionary(
        uniqueKeysWithValues: PenNode.NodeType.allCases.map { ($0, FieldIndex(type: $0)) }
    )
}
