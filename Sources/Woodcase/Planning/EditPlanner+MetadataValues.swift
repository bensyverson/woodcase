//
//  EditPlanner+MetadataValues.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Refuses a number written to a `metadata.woodcase` key outside the key's
    /// ``PenMetadata/WoodcaseKey/constraint``.
    ///
    /// A note's type size and line height live in its metadata because Pen strips them
    /// from the node, so they are held to the range of the `kind.` key they stand in for
    /// and refused the same way — ``EditRefusal/Code/outOfRange``, with the key's full
    /// path (`common.metadata.woodcase.fontSize`) as the property. Only what the write
    /// changes is judged, as everywhere else.
    ///
    /// - Parameters:
    ///   - props: The write, deep metadata keys already folded onto `common.metadata`.
    ///   - node: The node written, for the values it holds now.
    ///   - address: The address as written, for the refusal.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/outOfRange`` or
    ///   ``EditRefusal/Code/offStep``.
    static func checkMetadataValues(
        _ props: [String: AnyCodable],
        on node: PenNode,
        address: String
    ) throws {
        guard case let .dictionary(object)? = props[NodePropertyCodec.metadataPath] else { return }
        let written = PenMetadata(object: object)
        let current = node.common.metadata
        for key in PenMetadata.WoodcaseKey.allCases {
            guard let constraint = key.constraint, let value = written[woodcase: key],
                  value != current?[woodcase: key]
            else { continue }
            try checkConstraint(
                ValueWrite(key: key.path, field: key.rawValue, value: value, current: current?[woodcase: key]),
                constraint,
                address: address
            )
        }
    }
}
