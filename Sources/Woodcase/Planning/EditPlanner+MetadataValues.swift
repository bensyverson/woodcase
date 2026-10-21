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
    /// key named as the caller wrote it — `note.fontSize`, or `common.metadata.woodcase.fontSize` —
    /// as the property. Only what the write
    /// changes is judged, as everywhere else.
    ///
    /// - Parameters:
    ///   - props: The write, deep metadata keys already folded onto `common.metadata`.
    ///   - callerWrite: The write as the caller spelled it, which names the refused key
    ///     (``spelling(of:asWritten:)``).
    ///   - node: The node written, for the values it holds now.
    ///   - address: The address as written, for the refusal.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/outOfRange`` or
    ///   ``EditRefusal/Code/offStep``.
    static func checkMetadataValues(
        _ props: [String: AnyCodable],
        asWritten callerWrite: [String: AnyCodable],
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
                ValueWrite(
                    key: spelling(of: key, asWritten: callerWrite), field: key.rawValue, value: value,
                    current: current?[woodcase: key]
                ),
                constraint,
                address: address
            )
        }
    }

    /// The spelling a refusal names a Woodcase key by: the one the caller wrote.
    ///
    /// A key with an alias (`note.state`) is written either way, so a refusal echoes the
    /// spelling in the write — the natural path when the caller wrote it, or a deep key
    /// below it; otherwise the storage path, which is what a raw write, or a whole
    /// `common.metadata` object, spells.
    ///
    /// - Parameters:
    ///   - key: The refused key.
    ///   - written: The write as the caller spelled it.
    /// - Returns: The path to name.
    static func spelling(of key: PenMetadata.WoodcaseKey, asWritten written: [String: AnyCodable]) -> String {
        guard let natural = key.naturalPath,
              written.keys.contains(where: { $0 == natural || $0.hasPrefix(natural + ".") })
        else { return key.path }
        return natural
    }

    /// A post-it refusal with its key named as the caller wrote it (``spelling(of:asWritten:)``).
    ///
    /// - Parameters:
    ///   - error: The error the authoring check threw.
    ///   - written: The write as the caller spelled it.
    /// - Returns: The same error, respelled when it is a post-it refusal of a known key.
    static func respelled(_ error: Error, asWritten written: [String: AnyCodable]) -> Error {
        guard case let EditingError.postItMetadataRejected(nodeID, path, value, accepted, suggestion) = error,
              let key = PenMetadata.WoodcaseKey(rawValue: String(path.split(separator: ".").last ?? ""))
        else { return error }
        return EditingError.postItMetadataRejected(
            nodeID: nodeID, key: spelling(of: key, asWritten: written), value: value, accepted: accepted,
            suggestion: suggestion
        )
    }
}
