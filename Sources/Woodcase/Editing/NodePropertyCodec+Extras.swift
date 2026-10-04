//
//  NodePropertyCodec+Extras.swift
//  Woodcase
//

import Foundation

/// `extras.<key>`: one of a node's ``PenNode/extras`` as a property path.
///
/// A file can carry keys a node's type does not model, and Woodcase keeps them. Naming
/// them as paths lets a diff say "this extra changed" and an undo put one back, in the
/// same ``EditOperation/setProperties(_:)`` the modeled properties use — so the session's
/// change keys, the diff's output and the CRDT all speak one vocabulary.
///
/// Three rules keep a written extra from meaning something else when the file is read
/// back:
///
/// - the key must not be one the node's type claims (`extras.width` on a frame would be
///   decoded as its width);
/// - a `ref` takes none, because every key a ref does not claim is a root override;
/// - a node of a type Woodcase does not model takes none either, because all its keys
///   are already ``PenNode/Kind/unknown(typeName:properties:)`` properties, written as
///   `kind.<key>`.
///
/// An agent's `set` cannot write one: ``checkAuthored(_:on:)`` refuses the path, so a typo
/// is never kept as an extra.
public extension NodePropertyCodec {
    /// The prefix that turns a key the node's type does not model into a property path.
    static let extrasPrefix = "extras."

    /// Whether a path names one of a node's extras.
    ///
    /// - Parameter path: A property path.
    /// - Returns: `true` for an `extras.<key>` path, valid or not.
    static func isExtrasPath(_ path: String) -> Bool {
        path.hasPrefix(extrasPrefix)
    }
}

extension NodePropertyCodec {
    /// Reads one extra.
    ///
    /// - Parameters:
    ///   - path: An `extras.<key>` path.
    ///   - node: The node to read from.
    /// - Returns: The kept value, or ``AnyCodable/null`` if the node has no such extra.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` for a key the
    ///   node cannot carry as an extra.
    static func extraValue(at path: String, of node: PenNode) throws -> AnyCodable {
        try node.extras[extraKey(of: path, on: node)] ?? .null
    }

    /// Returns a copy of `node` with one extra set, or removed by ``AnyCodable/null``.
    ///
    /// - Parameters:
    ///   - value: The new value.
    ///   - path: An `extras.<key>` path.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` for a key the
    ///   node cannot carry as an extra.
    static func settingExtra(_ value: AnyCodable, at path: String, on node: PenNode) throws -> PenNode {
        let key = try extraKey(of: path, on: node)
        var values = node.extras.values
        if case .null = value {
            values.removeValue(forKey: key)
        } else {
            values[key] = value
        }
        var patched = node
        patched.extras = PenExtras(values)
        return patched
    }

    /// The raw key an `extras.<key>` path names, refusing one the node cannot carry.
    ///
    /// - Parameters:
    ///   - path: An `extras.<key>` path.
    ///   - node: The node it addresses.
    /// - Returns: The raw key.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)``.
    private static func extraKey(of path: String, on node: PenNode) throws -> String {
        let key = String(path.dropFirst(extrasPrefix.count))
        guard isExtrasPath(path), !key.isEmpty,
              let type = PenNode.NodeType(rawValue: node.kind.typeName), type != .ref,
              let claimed = PenNode.claimedKeys[type], !claimed.contains(key)
        else {
            throw unknownProperty(path, node.id, node.kind.typeName)
        }
        return key
    }
}
