//
//  NodePropertyCodec.swift
//  Woodcase
//

import Foundation

/// Reads and writes a single node property addressed by a dotted path.
///
/// The path vocabulary is the one ``PropertyDiff`` emits and ``LWWPropertyMap``
/// keys on — `"common.name"`, `"kind.width"`, `"kind.fills"` — so an edit, a
/// CRDT write and a dirty-tracking diff all name a property the same way.
///
/// Values are ``AnyCodable`` in the **.pen file's own JSON shape**: a number is
/// `42`, a variable reference is `"$spacing.large"`, a fill is whatever the
/// `fill` key holds in the file. Reading a property and writing the result back
/// is a no-op.
///
/// Unlike the CRDT's remote-operation path, every entry point here **throws**:
/// a key that is not a property of this node's kind raises
/// ``EditingError/unknownProperty(nodeID:key:nodeType:)``, and a value that
/// cannot decode to the property's type raises
/// ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``. Callers
/// that must not fail — applying a remote peer's operation — use `try?`.
///
/// ```swift
/// let node = document.node(id: "r1")!
/// NodePropertyCodec.paths(for: node)                    // ["common.context", …, "kind.width"]
/// try NodePropertyCodec.value(at: "kind.width", of: node)          // .int(100)
/// try NodePropertyCodec.setting(.int(200), at: "kind.width", on: node)
/// ```
///
/// ## Limits of the vocabulary
///
/// - `"kind.type"` is not a path. ``PropertyDiff`` emits it to mark a whole-kind
///   swap; changing a node's type is ``EditOperation/updateKind(_:)``'s job.
/// - A node of an unrecognized type (``PenNode/Kind/unknown(typeName:properties:)``)
///   is the one node whose vocabulary is open: ``paths(for:)`` lists the keys it
///   already carries, but any `kind.*` key can be written, because Woodcase has
///   no schema for that type to check one against.
public enum NodePropertyCodec {
    // MARK: - Vocabulary

    /// Every `common.*` path, valid on a node of any kind.
    ///
    /// `NodePropertyCodecTests` pins this to the set ``PropertyDiff/diffCommon(old:new:)``
    /// can emit, so the two never drift.
    public static let commonPaths: Set<String> = [
        "common.name", "common.x", "common.y", "common.rotation", "common.opacity",
        "common.enabled", "common.flipX", "common.flipY", "common.reusable",
        "common.theme", "common.context", "common.layoutPosition", "common.metadata",
    ]

    /// Every property path that can be read from or written to this node, sorted.
    ///
    /// - Parameter node: The node whose vocabulary to list.
    /// - Returns: The `common.*` paths followed by the `kind.*` paths of the
    ///   node's own kind, in one sorted array.
    public static func paths(for node: PenNode) -> [String] {
        commonPaths.union(PropertyDiff.allKindKeys(node.kind)).sorted()
    }

    // MARK: - Reading

    /// Reads the value at a property path as it would appear in a .pen file.
    ///
    /// - Parameters:
    ///   - path: A path from ``paths(for:)``.
    ///   - node: The node to read from.
    /// - Returns: The property's JSON value, or ``AnyCodable/null`` if it is unset.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` if the path
    ///   is not a property of this node's kind.
    public static func value(at path: String, of node: PenNode) throws -> AnyCodable {
        if path.hasPrefix("common.") {
            return try commonValue(at: path, of: node.common, nodeID: node.id, nodeType: node.kind.typeName)
        }
        if path.hasPrefix("kind.") {
            return try kindValue(at: path, of: node.kind, nodeID: node.id)
        }
        throw unknownProperty(path, node.id, node.kind.typeName)
    }

    /// Reads the value at a `common.*` path.
    ///
    /// - Parameters:
    ///   - path: A path from ``commonPaths``.
    ///   - common: The shared properties to read from.
    ///   - nodeID: The owning node's ID, for error reporting.
    ///   - nodeType: The owning node's type name, for error reporting.
    /// - Returns: The property's JSON value, or ``AnyCodable/null`` if it is unset.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` for a path
    ///   that is not a common property.
    static func commonValue(
        at path: String,
        of common: PenNodeCommon,
        nodeID: String,
        nodeType: String
    ) throws -> AnyCodable {
        guard commonPaths.contains(path) else { throw unknownProperty(path, nodeID, nodeType) }
        let field = String(path.dropFirst(commonPrefix.count))
        return try dictionary(from: common)[jsonKey(for: field)] ?? .null
    }

    /// Reads the value at a `kind.*` path.
    ///
    /// - Parameters:
    ///   - path: A path from ``PropertyDiff/allKindKeys(_:)`` for this kind.
    ///   - kind: The kind-specific data to read from.
    ///   - nodeID: The owning node's ID, for error reporting.
    /// - Returns: The property's JSON value, or ``AnyCodable/null`` if it is unset.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` for a path
    ///   that is not a property of this kind.
    static func kindValue(at path: String, of kind: PenNode.Kind, nodeID: String) throws -> AnyCodable {
        let field = try kindField(of: path, in: kind, nodeID: nodeID)

        switch kind {
        case let .unknown(_, properties):
            return properties[field] ?? .null
        case let .ref(data):
            switch field {
            case "ref": return .string(data.ref)
            case "descendants": return try encode(data.descendants)
            default: return data.rootOverrides.map { .dictionary($0) } ?? .null
            }
        default:
            return try kindDictionary(kind)[jsonKey(for: field)] ?? .null
        }
    }

    // MARK: - Path helpers

    static let commonPrefix = "common."
    static let kindPrefix = "kind."

    /// Validates a `kind.*` path against a kind's vocabulary and returns its field name.
    ///
    /// A node of an unrecognized type is the one open case: Woodcase has no schema
    /// to check a key against, it keeps whatever keys the file carried, and a peer
    /// must be able to replicate a key this replica has not seen yet — so any
    /// `kind.*` path is accepted there.
    static func kindField(of path: String, in kind: PenNode.Kind, nodeID: String) throws -> String {
        guard path.hasPrefix(kindPrefix) else {
            throw unknownProperty(path, nodeID, kind.typeName)
        }
        let field = String(path.dropFirst(kindPrefix.count))
        if case .unknown = kind { return field }
        guard PropertyDiff.allKindKeys(kind).contains(path) else {
            throw unknownProperty(path, nodeID, kind.typeName)
        }
        return field
    }

    /// The error for a path that is not a property of this node.
    static func unknownProperty(_ path: String, _ nodeID: String, _ nodeType: String) -> EditingError {
        .unknownProperty(nodeID: nodeID, key: path, nodeType: nodeType)
    }

    /// The error for a value that cannot decode to a known property's type,
    /// carrying the shape that would have been accepted and what in the value was not.
    ///
    /// - Parameters:
    ///   - path: The property path the caller wrote.
    ///   - field: The path's field name, which selects the expected shape.
    ///   - value: The value the caller wrote.
    ///   - nodeID: The node it was written to.
    ///   - failure: The error the decode raised, when one is at hand. A structured
    ///     value needs it: `[{"type":"solid"}]` is an array, arrays are accepted, and
    ///     only the decode knows that element 0's spelling is the part that is wrong.
    /// - Returns: The mismatch to throw.
    static func mismatch(
        _ path: String,
        _ field: String,
        _ value: AnyCodable,
        _ nodeID: String,
        _ failure: Error? = nil
    ) -> EditingError {
        .propertyTypeMismatch(
            nodeID: nodeID,
            key: path,
            expected: expectedShape(of: field),
            actual: actualShape(of: value, field: field, failure: failure)
        )
    }

    /// Sets or clears one JSON key in a property dictionary.
    static func patching(
        _ dictionary: [String: AnyCodable],
        field: String,
        value: AnyCodable
    ) -> [String: AnyCodable] {
        var patched = dictionary
        let key = jsonKey(for: field)
        if case .null = value {
            patched.removeValue(forKey: key)
        } else {
            patched[key] = value
        }
        return patched
    }
}
