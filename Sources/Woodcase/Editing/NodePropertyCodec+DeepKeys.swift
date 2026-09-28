//
//  NodePropertyCodec+DeepKeys.swift
//  Woodcase
//

import Foundation

/// Writing *one key* of a property whose value is a whole object.
///
/// `common.metadata` is a single property holding an open object, so the only way to
/// annotate a node used to be to write the object out again — and every write that did
/// so silently dropped `_props`, `_role` and everything else already in it. A deep key
/// says which entry is meant: `common.metadata._role=button` merges one key and leaves
/// the rest exactly as they were, and `common.metadata._props.label=Body/Title`
/// reaches one entry inside a nested object.
///
/// The fold happens in the library, before an ``EditOperation`` exists, so what is
/// recorded — and replicated, and undone — is an ordinary whole-object write to
/// ``deepKeyedPaths``. Nothing downstream has to learn a second key form.
///
/// ```swift
/// NodePropertyCodec.deepKey(of: "common.metadata._props.label")
/// // (property: "common.metadata", keyPath: ["_props", "label"])
/// ```
public extension NodePropertyCodec {
    /// The whole-object properties a dotted key may reach inside.
    ///
    /// Only these take deep keys. Every other property keeps its plain meaning, so
    /// `common.name.first` is the unknown property it has always been rather than a
    /// silent write into a string.
    static let deepKeyedPaths: Set<String> = ["common.metadata"]

    /// Splits a deep key into the property it writes into and the key path inside it.
    ///
    /// - Parameter path: The key as written, such as `common.metadata._role`.
    /// - Returns: The whole-object property and the keys to walk inside it, or `nil`
    ///   when the path is not a deep key at all.
    static func deepKey(of path: String) -> (property: String, keyPath: [String])? {
        for property in deepKeyedPaths.sorted() where path.hasPrefix("\(property).") {
            let inside = String(path.dropFirst(property.count + 1))
            let keyPath = inside.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !keyPath.isEmpty, !keyPath.contains(where: \.isEmpty) else { return nil }
            return (property, keyPath)
        }
        return nil
    }

    /// Folds every deep key in a property map onto the object the node already carries.
    ///
    /// A whole-object write to the same property is applied *first* and the deep keys
    /// merge onto it, so `common.metadata={"type":"component"}` alongside
    /// `common.metadata._role=button` means the object it reads as. A deep key whose
    /// value is ``AnyCodable/null`` removes that entry, which is the same rule a null
    /// follows everywhere else.
    ///
    /// `common.metadata` carries one more rule: the `.pen` schema requires the object's
    /// `type` key, and ``PenMetadata`` itself no longer fabricates one — it leaves
    /// `type` exactly as the file had it, `nil` included, so a read-modify-write of an
    /// untouched node adds no key. A deep key that *creates* the object from nothing is
    /// a genuine write, though, so it chooses `"unknown"` here rather than leave the
    /// object schema-invalid; a write that already named a real type is untouched.
    ///
    /// - Parameters:
    ///   - properties: The properties as the caller wrote them.
    ///   - node: The node they will be written to, for the object as it stands.
    /// - Returns: The same properties with every deep key folded into one whole-object
    ///   value, ready for ``setting(_:at:on:)``.
    /// - Throws: ``EditingError/unknownProperty(nodeID:key:nodeType:)`` if a deep-keyed
    ///   property is somehow not a property of this node.
    static func folding(
        _ properties: [String: AnyCodable],
        onto node: PenNode
    ) throws -> [String: AnyCodable] {
        var folded: [String: AnyCodable] = [:]
        var deep: [String: [(keyPath: [String], value: AnyCodable)]] = [:]
        for (key, value) in properties {
            if let (property, keyPath) = deepKey(of: key) {
                deep[property, default: []].append((keyPath, value))
            } else {
                folded[key] = value
            }
        }
        for (property, writes) in deep.sorted(by: { $0.key < $1.key }) {
            let base = try folded[property] ?? value(at: property, of: node)
            var object = objectValue(of: base)
            for write in writes.sorted(by: { $0.keyPath.lexicographicallyPrecedes($1.keyPath) }) {
                object = merging(write.value, at: write.keyPath, into: object)
            }
            if property == metadataProperty, object["type"] == nil {
                object["type"] = .string(defaultMetadataType)
            }
            folded[property] = .dictionary(object)
        }
        return folded
    }

    /// The one deep-keyed property the schema requires a `type` key on.
    private static let metadataProperty = "common.metadata"

    /// What a deep key writes as `type` when it creates a metadata object with none.
    private static let defaultMetadataType = "unknown"

    // MARK: - Private

    /// The object a value stands for: its own keys, or none at all.
    private static func objectValue(of value: AnyCodable) -> [String: AnyCodable] {
        guard case let .dictionary(object) = value else { return [:] }
        return object
    }

    /// Writes one value at a key path inside an object, creating the objects on the way.
    ///
    /// A null removes the entry, and an object a null empties is removed with it, so
    /// clearing the last declared parameter leaves no `_props: {}` behind.
    private static func merging(
        _ value: AnyCodable,
        at keyPath: [String],
        into object: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        guard let head = keyPath.first else { return object }
        var patched = object
        guard keyPath.count > 1 else {
            if case .null = value {
                patched.removeValue(forKey: head)
            } else {
                patched[head] = value
            }
            return patched
        }
        let merged = merging(value, at: Array(keyPath.dropFirst()), into: objectValue(of: patched[head] ?? .null))
        if merged.isEmpty {
            patched.removeValue(forKey: head)
        } else {
            patched[head] = .dictionary(merged)
        }
        return patched
    }
}
