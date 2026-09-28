//
//  SchemaOverviewReport.swift
//  Woodcase
//

import Foundation

/// The whole .pen vocabulary — every node type, the shared properties, and the keys the
/// document root carries beside its nodes — flattened for a machine reader.
///
/// What `woodcase schema --json` prints with no type named, and what a script's
/// `doc.schema()` returns. It describes the *format*, not any one document, so it can
/// be built before a `.pen` file exists — which is when a caller most needs it.
public struct SchemaOverviewReport: Friendly {
    /// Builds the overview.
    public init() {
        types = PenNode.NodeType.allCases.map(NodeType.init)
        common = PenSchema.common.properties.map(SchemaPropertyReport.init)
        nested = PenSchema.nestedShapes.map(SchemaNestedReport.init)
        root = PenSchema.rootShapes.map(SchemaNestedReport.init)
    }

    /// Every node type the format has, in reading order.
    public let types: [NodeType]

    /// The properties every node of every type takes.
    public let common: [SchemaPropertyReport]

    /// Every nested key table any property of any type references.
    public let nested: [SchemaNestedReport]

    /// The key tables of the document root's own structured keys — `fonts`.
    public let root: [SchemaNestedReport]

    // MARK: - NodeType

    /// One node type, and what it is.
    public struct NodeType: Friendly {
        /// Names one type.
        ///
        /// - Parameter type: The type to publish.
        public init(_ type: PenNode.NodeType) {
            self.type = type.rawValue
            summary = type.summary
        }

        /// The type's name, as a .pen file writes it.
        public let type: String

        /// One phrase saying what a node of this type is.
        public let summary: String
    }
}
