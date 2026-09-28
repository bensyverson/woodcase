//
//  PenNode+ConnectionSchema.swift
//  Woodcase
//

import Foundation

/// The key table a connection's `source` and `target` take, declared beside the type
/// that decodes them.
public extension PenNode.ConnectionData {
    /// One end of a connection, as `woodcase schema connection` prints it.
    static let endpointSchema = PenNestedShape(
        name: "endpoint",
        singular: "an endpoint object",
        plural: "an array of endpoint objects",
        summary: "a node, by id or instance/child path, and the point on its box the connector meets",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "path", forms: [.text(.plain)], isRequired: true),
                PenNestedShape.Field(key: "anchor", forms: Anchor.allCases.map { .spelling($0.rawValue) }, isRequired: true),
            ]),
        ]
    )
}
