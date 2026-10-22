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
/// A `kind.*` natural path belongs to a node exactly when its type's vocabulary lists it
/// (``PropertyDiff/allKindKeys(_:)-(PenNode.Kind)``); on any other node it is the unknown
/// property it always was. A `common.*` one (``naturalCommonPaths``) belongs to every node.
///
/// The storage path is Woodcase's to write: a caller's write there is refused, naming the
/// natural path (``checkNoStoragePaths(_:nodeID:)``).
public extension NodePropertyCodec {
    /// The Woodcase key a path stands for on a node of this kind, or `nil` when the path is
    /// no natural path, or not one this kind takes.
    ///
    /// - Parameters:
    ///   - path: A property path, such as `kind.blendMode`.
    ///   - kind: The node's kind.
    /// - Returns: The key the path is stored under.
    static func naturalKey(of path: String, on kind: PenNode.Kind) -> PenMetadata.WoodcaseKey? {
        guard let key = PenMetadata.WoodcaseKey(naturalPath: path) else { return nil }
        if naturalCommonPaths.contains(path) || naturalCodegenPaths.contains(path) { return key }
        if naturalNotePaths.contains(path) { return notePaths(on: kind).contains(path) ? key : nil }
        guard kind.nodeType != nil, PropertyDiff.allKindKeys(kind).contains(path) else { return nil }
        return key
    }

    /// Whether a property map writes any natural path on a node of this kind.
    ///
    /// - Parameters:
    ///   - properties: The writes, by property path.
    ///   - kind: The node's kind.
    /// - Returns: `true` when ``storingNaturalPaths(_:on:)`` would rewrite a key: a natural
    ///   path, or a `spread` on a shadow in `kind.effects`.
    static func writesNaturalPath(_ properties: [String: AnyCodable], on kind: PenNode.Kind) -> Bool {
        properties.keys.contains { naturalKey(of: $0, on: kind) != nil || naturalStoragePath(of: $0) != nil }
            || writesNamedSpread(properties, on: kind)
    }

    /// The storage path a deep key below a natural path writes: `codegen.props.label` is
    /// `common.metadata.woodcase.props.label`.
    ///
    /// Only the code-generation paths take deep keys: `codegen.props` and `codegen.states`
    /// hold objects a caller writes one entry of, as they did at their storage paths.
    ///
    /// - Parameter path: A property path.
    /// - Returns: The deep storage key, or `nil` when the path is no deep key below a
    ///   `codegen.*` path.
    static func naturalStoragePath(of path: String) -> String? {
        guard path.hasPrefix(codegenPrefix) else { return nil }
        for natural in naturalCodegenPaths where path.hasPrefix(natural + ".") {
            guard let key = PenMetadata.WoodcaseKey(naturalPath: natural) else { return nil }
            let below = path.dropFirst(natural.count + 1)
            guard !below.isEmpty, !below.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty)
            else { return nil }
            return "\(key.path).\(below)"
        }
        return nil
    }

    /// Whether a write at this path lands in the node's metadata: `common.metadata`, a
    /// natural path the kind takes, or a deep key below a `codegen.*` path.
    ///
    /// - Parameters:
    ///   - path: A property path.
    ///   - kind: The node's kind.
    /// - Returns: `true` for a metadata write.
    static func writesMetadata(at path: String, on kind: PenNode.Kind) -> Bool {
        path == metadataPath || naturalKey(of: path, on: kind) != nil || naturalStoragePath(of: path) != nil
    }

    /// The writes with every natural path aimed at the deep key it is stored under.
    ///
    /// `kind.blendMode=multiply` becomes `common.metadata.woodcase.blendMode=multiply`, which
    /// ``folding(_:onto:)`` then merges onto the metadata the node carries. A value of the
    /// wrong form is refused here, under the path the caller wrote. A `kind.effects` whose
    /// shadows name a `spread` leaves it without them, and its spreads become a write of
    /// `common.metadata.woodcase.shadowSpread` (``restatingShadowSpreads(_:on:)``).
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
        let properties = try storingNamedSpreads(properties, on: node)
        var stored: [String: AnyCodable] = [:]
        // Two spellings of one storage key keep the later one in the application order.
        for (path, value) in applicationOrder(of: properties) {
            if let storage = naturalStoragePath(of: path) {
                stored[storage] = value
                continue
            }
            guard let key = naturalKey(of: path, on: node.kind) else {
                stored[path] = value
                continue
            }
            try checkNaturalValue(value, at: path, for: key, nodeID: node.id)
            stored[key.path] = value
        }
        return stored
    }

    /// Refuses a caller's write that names a Woodcase-owned key at its storage path.
    ///
    /// `common.metadata.woodcase.strokeDash` — or a deep key below it — is where the codec
    /// stores `kind.strokeDash`, not a second way in: two spellings of one write drift
    /// apart. Keys with no natural path, and the whole `common.metadata` object, are
    /// written as given.
    ///
    /// - Parameters:
    ///   - properties: The writes, by property path or raw key.
    ///   - nodeID: The node written to, for the error.
    /// - Throws: ``EditingError/storedAtNaturalPath(nodeID:path:naturalPath:)`` for the first
    ///   such path, in sorted order.
    static func checkNoStoragePaths(_ properties: [String: AnyCodable], nodeID: String) throws {
        for path in properties.keys.sorted() {
            guard let key = PenMetadata.WoodcaseKey(storagePath: path), let natural = key.writtenThrough else { continue }
            // A deep key below a code-generation key names the same deep key below its path,
            // the one kind of natural path that takes deep keys (`naturalStoragePath(of:)`).
            let below = path.dropFirst(key.path.count)
            let named = natural.hasPrefix(codegenPrefix) && below.hasPrefix(".") ? natural + below : natural
            throw EditingError.storedAtNaturalPath(nodeID: nodeID, path: path, naturalPath: named)
        }
    }

    /// The Woodcase-owned values a node sets, at their natural paths.
    ///
    /// What `get` prints beside the node JSON, which keeps them in `metadata.woodcase`.
    ///
    /// - Parameter node: The node to read.
    /// - Returns: Each natural path the node takes and sets, with its value; unset paths left
    ///   out. A node that draws a shadow with a spread lists `kind.effects` too, each shadow
    ///   carrying its spread (``presentedValue(at:of:)``).
    static func naturalValues(of node: PenNode) -> [String: AnyCodable] {
        var values: [String: AnyCodable] = [:]
        for key in PenMetadata.WoodcaseKey.allCases {
            guard let path = key.naturalPath, naturalKey(of: path, on: node.kind) != nil else { continue }
            let value = naturalValue(of: key, on: node)
            if value != .null { values[path] = value }
        }
        if takesEffects(node.kind), showsShadowSpread(node), let effects = try? presentedValue(at: effectsPath, of: node) {
            values[effectsPath] = effects
        }
        return values
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
