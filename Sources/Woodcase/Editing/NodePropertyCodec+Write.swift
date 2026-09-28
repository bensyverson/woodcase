//
//  NodePropertyCodec+Write.swift
//  Woodcase
//

import Foundation

/// The writing half of ``NodePropertyCodec``.
///
/// Every entry point returns a *copy* with one property changed, so a caller
/// patching several paths can fold them onto a scratch value and commit only
/// once every key and value has been accepted — which is how
/// ``EditOperation/setProperties(_:)`` stays atomic.
extension NodePropertyCodec {
    /// Returns a copy of `node` with one property set to `value`.
    ///
    /// Writing ``AnyCodable/null`` clears the property. Every other field of the
    /// node is left exactly as it was.
    ///
    /// This is the single funnel every verb's property write goes through, so it is
    /// where a number written to a text property becomes the string it spells — see
    /// ``coercing(_:at:on:)``. Nothing else about the value changes.
    ///
    /// - Parameters:
    ///   - value: The new JSON value, in the .pen file's own shape.
    ///   - path: A path from ``paths(for:)``.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` if the path
    ///   is not a property of this node's kind, or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)`` if the
    ///   value cannot decode to the property's type.
    public static func setting(_ value: AnyCodable, at path: String, on node: PenNode) throws -> PenNode {
        let written = coercing(value, at: path, on: node.kind)
        var patched = node
        if path.hasPrefix(commonPrefix) {
            patched.common = try setting(
                written, at: path, on: node.common, nodeID: node.id, nodeType: node.kind.typeName
            )
        } else if path.hasPrefix(kindPrefix) {
            patched.kind = try setting(written, at: path, on: node.kind, nodeID: node.id)
        } else {
            throw unknownProperty(path, node.id, node.kind.typeName)
        }
        return patched
    }

    /// Returns a copy of `common` with one shared property set to `value`.
    ///
    /// - Parameters:
    ///   - value: The new JSON value; ``AnyCodable/null`` clears the property.
    ///   - path: A path from ``commonPaths``.
    ///   - common: The shared properties to patch.
    ///   - nodeID: The owning node's ID, for error reporting.
    ///   - nodeType: The owning node's type name, for error reporting.
    /// - Returns: The patched shared properties.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    static func setting(
        _ value: AnyCodable,
        at path: String,
        on common: PenNodeCommon,
        nodeID: String,
        nodeType: String
    ) throws -> PenNodeCommon {
        guard commonPaths.contains(path) else { throw unknownProperty(path, nodeID, nodeType) }
        let field = String(path.dropFirst(commonPrefix.count))
        let patched = try patching(dictionary(from: common), field: field, value: value)
        do {
            return try decode(PenNodeCommon.self, from: patched)
        } catch {
            throw mismatch(path, field, value, nodeID, error)
        }
    }

    /// Returns a copy of `kind` with one kind-specific property set to `value`.
    ///
    /// - Parameters:
    ///   - value: The new JSON value; ``AnyCodable/null`` clears the property.
    ///   - path: A path from ``PropertyDiff/allKindKeys(_:)`` for this kind.
    ///   - kind: The kind-specific data to patch.
    ///   - nodeID: The owning node's ID, for error reporting.
    /// - Returns: The patched kind.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    static func setting(
        _ value: AnyCodable,
        at path: String,
        on kind: PenNode.Kind,
        nodeID: String
    ) throws -> PenNode.Kind {
        let field = try kindField(of: path, in: kind, nodeID: nodeID)

        switch kind {
        case let .unknown(typeName, properties):
            var properties = properties
            if case .null = value {
                properties.removeValue(forKey: field)
            } else {
                properties[field] = value
            }
            return .unknown(typeName: typeName, properties: properties)

        case var .ref(data):
            switch field {
            case "ref":
                guard case let .string(name) = value else { throw mismatch(path, field, value, nodeID) }
                data.ref = name
            case "descendants":
                if case .null = value {
                    data.descendants = nil
                } else {
                    do {
                        data.descendants = try decode([String: PenDescendantOverride].self, fromValue: value)
                    } catch {
                        throw mismatch(path, field, value, nodeID, error)
                    }
                }
            default:
                switch value {
                case .null: data.rootOverrides = nil
                case let .dictionary(overrides): data.rootOverrides = overrides
                default: throw mismatch(path, field, value, nodeID)
                }
            }
            return .ref(data)

        default:
            let patched = try patching(kindDictionary(kind), field: field, value: value)
            do {
                return try makeKind(like: kind, from: patched)
            } catch {
                throw mismatch(path, field, value, nodeID, error)
            }
        }
    }
}
