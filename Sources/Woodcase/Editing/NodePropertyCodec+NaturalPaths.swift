//
//  NodePropertyCodec+NaturalPaths.swift
//  Woodcase
//

import Foundation

/// Reading and writing a Woodcase key at its natural path.
///
/// A key that stands in for a property Pen's format lacks names a natural path
/// (``PenMetadata/WoodcaseKey/naturalPath``) — `kind.blendMode` — and is stored in
/// `metadata.woodcase`, which Pen keeps. A caller reads and writes the natural path; the
/// codec turns it into the storage path at the door, so what is planned, applied,
/// replicated and undone is the ordinary metadata write every other Woodcase key makes
/// (<doc:PenMetadataNamespace>).
///
/// A natural path belongs to a node exactly when its type's vocabulary lists it
/// (``PropertyDiff/allKindKeys(_:)-(PenNode.Kind)``); on any other node it is the unknown
/// property it always was.
public extension NodePropertyCodec {
    /// The Woodcase key a path stands for on a node of this kind, or `nil` when the path is
    /// no natural path, or not one this kind takes.
    ///
    /// - Parameters:
    ///   - path: A property path, such as `kind.blendMode`.
    ///   - kind: The node's kind.
    /// - Returns: The key the path is stored under.
    static func naturalKey(of path: String, on kind: PenNode.Kind) -> PenMetadata.WoodcaseKey? {
        guard let key = PenMetadata.WoodcaseKey(naturalPath: path), kind.nodeType != nil,
              PropertyDiff.allKindKeys(kind).contains(path)
        else { return nil }
        return key
    }

    /// Whether a property map writes any natural path on a node of this kind.
    ///
    /// - Parameters:
    ///   - properties: The writes, by property path.
    ///   - kind: The node's kind.
    /// - Returns: `true` when ``storingNaturalPaths(_:on:)`` would rewrite a key.
    static func writesNaturalPath(_ properties: [String: AnyCodable], on kind: PenNode.Kind) -> Bool {
        properties.keys.contains { naturalKey(of: $0, on: kind) != nil }
    }

    /// The writes with every natural path aimed at the deep key it is stored under.
    ///
    /// `kind.blendMode=multiply` becomes `common.metadata.woodcase.blendMode=multiply`, which
    /// ``folding(_:onto:)`` then merges onto the metadata the node carries. A value of the
    /// wrong form is refused here, under the path the caller wrote.
    ///
    /// - Parameters:
    ///   - properties: The writes, by property path.
    ///   - node: The node written to.
    /// - Returns: The same writes, natural paths replaced by their storage.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)`` for a
    ///   value the key cannot hold.
    static func storingNaturalPaths(
        _ properties: [String: AnyCodable],
        on node: PenNode
    ) throws -> [String: AnyCodable] {
        guard writesNaturalPath(properties, on: node.kind) else { return properties }
        var stored: [String: AnyCodable] = [:]
        for (path, value) in properties {
            guard let key = naturalKey(of: path, on: node.kind) else {
                stored[path] = value
                continue
            }
            try checkNaturalValue(value, at: path, for: key, nodeID: node.id)
            stored[key.path] = value
        }
        return stored
    }

    // MARK: - Internal

    /// The value stored for a natural path, as ``value(at:of:)`` reads it.
    ///
    /// - Parameters:
    ///   - key: The key the path stands for.
    ///   - node: The node to read.
    /// - Returns: The stored value, or ``AnyCodable/null`` when there is none.
    internal static func naturalValue(of key: PenMetadata.WoodcaseKey, on node: PenNode) -> AnyCodable {
        node.common.metadata?[woodcase: key] ?? .null
    }

    /// Returns `node` with a natural path written: the metadata write it stands for,
    /// folded onto the metadata the node carries.
    ///
    /// - Parameters:
    ///   - value: The value; ``AnyCodable/null`` removes the key.
    ///   - path: The natural path.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    internal static func settingNaturalPath(_ value: AnyCodable, at path: String, on node: PenNode) throws -> PenNode {
        let folded = try folding([path: value], onto: node)
        return try setting(folded[metadataPath] ?? .null, at: metadataPath, on: node)
    }

    /// Holds a natural path's value to the form its key takes: a string for a key of
    /// ``PenMetadata/WoodcaseKey/Shape/string`` shape, as the `kind.` property it replaced
    /// was. Every other form is held by the authoring check, as the key's storage path is.
    private static func checkNaturalValue(
        _ value: AnyCodable, at path: String, for key: PenMetadata.WoodcaseKey, nodeID: String
    ) throws {
        switch (key.shape, value) {
        case (_, .null), (.string, .string): return
        case (.string, _): throw mismatch(path, fieldName(of: path) ?? path, value, nodeID)
        default: return
        }
    }
}
