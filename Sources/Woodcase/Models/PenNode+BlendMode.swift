//
//  PenNode+BlendMode.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The node types that take a blend mode of their own: the drawn shapes, text, icons and
    /// the two containers.
    static let blendedTypes: Set<NodeType> = [
        .frame, .group, .rectangle, .ellipse, .polygon, .path, .line, .text, .icon,
    ]

    /// How the node, drawn as one isolated group, composites onto what lies beneath it:
    /// its ``PenMetadata/WoodcaseKey/blendMode``, or `nil` where it has none.
    ///
    /// Pen's format gives a blend mode only to paints and shadows, and Pen drops a node's
    /// top-level `blendMode` on load, so a node's own lives in `metadata.woodcase`, which
    /// Pen keeps (Ben's ruling of 2026-10-20). A file, an `add` or an override that still
    /// writes it top-level is read into metadata, and a write never emits the top-level
    /// key. Callers read and write it at `kind.blendMode`, as before.
    ///
    /// Only the ``blendedTypes`` have one: on any other node this is `nil`, and setting it
    /// does nothing. A key that is not a string is no blend mode; a string Woodcase does
    /// not know is ``PenBlendMode/unknown(_:)``, kept as written. Setting `nil` removes the
    /// key, and metadata it leaves holding nothing but Woodcase's own type with it.
    var blendMode: PenBlendMode? {
        get {
            guard takesBlendMode, case let .string(raw)? = common.metadata?[woodcase: .blendMode] else { return nil }
            return PenBlendMode(rawString: raw)
        }
        set {
            guard takesBlendMode else { return }
            common.metadata = Self.metadata(common.metadata, blendMode: newValue)
        }
    }

    /// Whether the node's type takes a blend mode of its own.
    internal var takesBlendMode: Bool {
        kind.nodeType.map(Self.blendedTypes.contains) ?? false
    }

    /// The shared properties of a node object being decoded, with a top-level `blendMode`
    /// it still writes moved into `metadata.woodcase`.
    ///
    /// The top-level key wins over a blend the metadata already holds: an override is
    /// merged onto the component node's own object, so a top-level `blendMode` beside that
    /// node's stored one is the override's, and must show. A file never writes both.
    ///
    /// - Parameters:
    ///   - common: The node's decoded shared properties.
    ///   - decoder: The decoder positioned at the node object.
    /// - Returns: `common`, with the blend moved in when the object writes one.
    /// - Throws: `DecodingError` for a top-level `blendMode` that is not a string, as
    ///   decoding it into the node's data always did.
    internal static func migratingTopLevelBlendMode(_ common: PenNodeCommon, from decoder: Decoder) throws -> PenNodeCommon {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let key = DynamicCodingKey(stringValue: topLevelBlendModeKey)
        guard container.contains(key), let mode = try container.decodeIfPresent(PenBlendMode.self, forKey: key) else {
            return common
        }
        var migrated = common
        migrated.metadata = metadata(common.metadata, blendMode: mode)
        return migrated
    }

    /// The key a node's blend mode was written under before it moved into metadata.
    internal static let topLevelBlendModeKey = "blendMode"

    /// `metadata` with its blend key set to `mode`, or removed for `nil`.
    ///
    /// - Parameters:
    ///   - metadata: The node's metadata, or `nil` for none.
    ///   - mode: The blend mode to store.
    /// - Returns: The metadata to store, or `nil` when it holds nothing but Woodcase's type.
    internal static func metadata(_ metadata: PenMetadata?, blendMode mode: PenBlendMode?) -> PenMetadata? {
        var updated = metadata ?? PenMetadata(type: nil)
        updated[woodcase: .blendMode] = mode.map { .string($0.rawString) }
        return updated.typedForWriting()
    }
}
