//
//  PenNode+NaturalKeyMigration.swift
//  Woodcase
//

import Foundation

extension PenNode {
    /// The shared properties of a node object being decoded, with every natural-path field
    /// it writes top-level — `blendMode`, `strokeDash`, `locked` — moved into
    /// `metadata.woodcase`, where Woodcase stores it (``PenMetadata/WoodcaseKey/naturalPath``).
    ///
    /// Nothing Woodcase writes puts them there, but a file from before a key moved into
    /// metadata (a node `blendMode`), an `add` of a node written in Pen's style, and an
    /// instance override can. An override is stored under the raw key and merged onto the
    /// component node's own object before it is decoded (``PenNodePatcher``), so this is what
    /// reads it into that node's metadata **key by key**: the component's other keys stay,
    /// and later edits to them still reach the instance. The top-level key wins over a value
    /// the metadata already holds, since beside a component node's stored value it is the
    /// override's. A `ref` is left alone: its top-level keys are root overrides.
    ///
    /// - Parameters:
    ///   - common: The node's decoded shared properties.
    ///   - type: The node's modeled type.
    ///   - decoder: The decoder positioned at the node object.
    /// - Returns: `common`, with each field the type takes moved in.
    /// - Throws: `DecodingError` for a top-level `blendMode` that is not a string, as
    ///   decoding it into the node's data always did.
    static func migratingTopLevelNaturalKeys(
        _ common: PenNodeCommon, of type: NodeType, from decoder: Decoder
    ) throws -> PenNodeCommon {
        guard type != .ref else { return common }
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var migrated = common
        for codingKey in container.allKeys {
            guard let key = PenMetadata.WoodcaseKey(naturalField: codingKey.stringValue),
                  key.naturalPathTypes.contains(type)
            else { continue }
            let value: AnyCodable = if key == .blendMode {
                try container.decodeIfPresent(PenBlendMode.self, forKey: codingKey).map { .string($0.rawString) } ?? .null
            } else {
                try container.decode(AnyCodable.self, forKey: codingKey)
            }
            var metadata = migrated.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: key] = value == .null ? nil : value
            migrated.metadata = metadata.typedForWriting()
        }
        return migrated
    }
}

extension PenNode {
    /// A `ref` node with every Woodcase-owned key its root overrides name raw (`blendMode`,
    /// written before rule 6, or by a raw operation) moved onto its own `metadata.woodcase`,
    /// where an instance root's override of one is stored and laid over the component
    /// root's key by key.
    ///
    /// A `null` removes the ref's key, so the root shows the component's.
    ///
    /// - Parameters:
    ///   - common: The ref node's shared properties.
    ///   - data: Its ref payload.
    /// - Returns: Both, with the keys moved; unchanged when the root overrides name none.
    static func movingRootNaturalKeys(
        _ common: PenNodeCommon, _ data: RefData
    ) -> (common: PenNodeCommon, data: RefData) {
        guard let overrides = data.rootOverrides,
              overrides.keys.contains(where: { NodePropertyCodec.naturalOverrideKey($0) != nil })
        else { return (common, data) }
        var common = common
        var data = data
        var metadata = common.metadata ?? PenMetadata(type: nil)
        var rest: [String: AnyCodable] = [:]
        for (name, value) in overrides {
            guard let key = NodePropertyCodec.naturalOverrideKey(name) else {
                rest[name] = value
                continue
            }
            metadata[woodcase: key] = value == .null ? nil : value
        }
        common.metadata = metadata.typedForWriting()
        data.rootOverrides = rest.isEmpty ? nil : rest
        return (common, data)
    }
}
