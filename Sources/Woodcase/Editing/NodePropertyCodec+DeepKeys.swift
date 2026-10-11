//
//  NodePropertyCodec+DeepKeys.swift
//  Woodcase
//

import Foundation

/// Writing *one key* of a property whose value is a whole object.
///
/// `common.metadata` is a single property holding an open object, so the only way to
/// annotate a node used to be to write the object out again — and every write that did
/// so silently dropped everything else already in it. A deep key says which entry is
/// meant: `common.metadata.woodcase.role=button` merges one key and leaves the rest
/// exactly as they were, and `common.metadata.woodcase.props.label=Body/Title` reaches
/// one entry inside a nested object.
///
/// The fold happens in the library, before an ``EditOperation`` exists, so what is
/// recorded — and replicated, and undone — is an ordinary whole-object write to
/// ``deepKeyedPaths``. Nothing downstream has to learn a second key form.
///
/// ```swift
/// NodePropertyCodec.deepKey(of: "common.metadata.woodcase.props.label")
/// // (property: "common.metadata", keyPath: ["woodcase", "props", "label"])
/// ```
public extension NodePropertyCodec {
    /// The whole-object properties a dotted key may reach inside.
    ///
    /// Only these take deep keys. Every other property keeps its plain meaning, so
    /// `common.name.first` is the unknown property it has always been rather than a
    /// silent write into a string.
    static let deepKeyedPaths: Set<String> = [metadataPath]

    /// Splits a deep key into the property it writes into and the key path inside it.
    ///
    /// - Parameter path: The key as written, such as `common.metadata.woodcase.role`.
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
    /// `common.metadata.woodcase.role=button` means the object it reads as. A deep key whose
    /// value is ``AnyCodable/null`` removes that entry, which is the same rule a null
    /// follows everywhere else.
    ///
    /// `common.metadata` carries one more rule: the `.pen` schema requires the object's
    /// `type` key, and ``PenMetadata`` itself fabricates none — it leaves `type` exactly as
    /// the file had it, `nil` included, so a read-modify-write of an untouched node adds no
    /// key. A write *is* a write, though: an object it leaves without a type takes
    /// ``PenMetadata/woodcaseType`` (``storingWoodcaseKeysInNamespace(_:replacing:)``); a
    /// type anyone else wrote is untouched.
    ///
    /// Last, a metadata write — deep or whole — stores the Woodcase keys it changes
    /// under `metadata.woodcase` only (``storingWoodcaseKeysInNamespace(_:replacing:)``).
    ///
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
            var writes = writes
            if property == metadataPath {
                (object, writes) = aimingAtWoodcaseNamespace(writes, onto: object)
            }
            for write in writes.sorted(by: { $0.keyPath.lexicographicallyPrecedes($1.keyPath) }) {
                object = merging(write.value, at: write.keyPath, into: object)
            }
            folded[property] = .dictionary(object)
        }
        if case let .dictionary(metadata)? = folded[metadataPath] {
            folded[metadataPath] = storingWoodcaseKeysInNamespace(metadata, replacing: node.common.metadata)
                .map(AnyCodable.dictionary) ?? .null
        }
        return folded
    }

    // MARK: - Private

    /// The object a value stands for: its own keys, or none at all.
    private static func objectValue(of value: AnyCodable) -> [String: AnyCodable] {
        guard case let .dictionary(object) = value else { return [:] }
        return object
    }

    /// Writes one value at a key path inside an object, creating the objects on the way.
    ///
    /// A null removes the entry, and an object a null empties is removed with it, so
    /// clearing the last declared parameter leaves no `props: {}` behind.
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
