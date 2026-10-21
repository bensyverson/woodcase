//
//  NodePropertyCodec+MetadataEntries.swift
//  Woodcase
//

import Foundation

/// `common.metadata`, one entry at a time: the unit both merges resolve metadata on.
///
/// Metadata is one property in the codec's vocabulary, but two writers touching
/// different keys of one node's metadata — a note's tint and its state — must both
/// survive. So the CRDT replicates metadata as one write per **entry**, and the
/// three-way merge resolves it entry by entry. An entry is a top-level key of the
/// object, except the Woodcase namespace, which splits one level deeper: each key under
/// `metadata.woodcase` is its own entry. Below that a value is whole — two edits to
/// different parameters inside `codegen.props` are one entry both sides changed.
///
/// An entry's path is a deep key: `common.metadata.type`,
/// `common.metadata.woodcase.tint`. A key holding `.` or `%` is percent-escaped in it
/// (`%2E`, `%25`), so every key has exactly one path. See <doc:PenMetadataNamespace>.
public extension NodePropertyCodec {
    /// One entry of a node's metadata and the value it holds; ``AnyCodable/null`` when
    /// the entry is absent.
    struct MetadataEntry: Friendly {
        /// The entry's path, such as `common.metadata.woodcase.tint`.
        public var path: String
        /// The entry's value, or ``AnyCodable/null`` to remove it.
        public var value: AnyCodable
    }

    /// The entries a metadata object holds, by path.
    ///
    /// - Parameter metadata: The metadata, or `nil` for none.
    /// - Returns: Every entry's value, keyed by its path.
    static func metadataEntries(of metadata: PenMetadata?) -> [String: AnyCodable] {
        var entries: [String: AnyCodable] = [:]
        for (key, value) in metadata?.object ?? [:] {
            if key == PenMetadata.woodcaseNamespace, case let .dictionary(namespace) = value {
                for (inner, innerValue) in namespace {
                    entries[metadataEntryPath([key, inner])] = innerValue
                }
            } else {
                entries[metadataEntryPath([key])] = value
            }
        }
        return entries
    }

    /// The entry writes that turn one metadata object into another, sorted by path.
    ///
    /// A namespace that is not an object on either side is one entry, written whole.
    ///
    /// - Parameters:
    ///   - old: The metadata before.
    ///   - new: The metadata after.
    /// - Returns: One write per entry that differs; a removed entry writes
    ///   ``AnyCodable/null``.
    static func metadataEntryWrites(from old: PenMetadata?, to new: PenMetadata?) -> [MetadataEntry] {
        let before = metadataEntries(of: old)
        let after = metadataEntries(of: new)
        return Set(before.keys).union(after.keys).sorted().compactMap { path in
            let value = after[path] ?? .null
            return (before[path] ?? .null) == value ? nil : MetadataEntry(path: path, value: value)
        }
    }

    /// A node with one metadata entry written.
    ///
    /// The object is created when the node has none, and removed when the write leaves
    /// it empty; an emptied namespace is removed the same way. The entry is written
    /// exactly — no `type` is filled in — because a CRDT peer must land on what the
    /// writing peer's own store holds, and that store took the write exactly.
    ///
    /// - Parameters:
    ///   - value: The entry's value; ``AnyCodable/null`` removes it.
    ///   - path: The entry's path.
    ///   - node: The node to write.
    /// - Returns: The node with the entry written, or `nil` when `path` is not an entry.
    static func settingMetadataEntry(_ value: AnyCodable, at path: String, on node: PenNode) -> PenNode? {
        guard let keys = metadataEntryKeys(of: path) else { return nil }
        var object = node.common.metadata?.object ?? [:]
        if keys.count == 1 {
            write(value, at: keys[0], in: &object)
        } else {
            var namespace: [String: AnyCodable] = [:]
            if case let .dictionary(existing)? = object[keys[0]] { namespace = existing }
            write(value, at: keys[1], in: &namespace)
            write(namespace.isEmpty ? .null : .dictionary(namespace), at: keys[0], in: &object)
        }
        var written = node
        written.common.metadata = object.isEmpty ? nil : PenMetadata(object: object)
        return written
    }

    /// The path of the entry a key path inside the metadata object names.
    ///
    /// - Parameter keys: One key, or the namespace and a key under it.
    /// - Returns: The escaped deep-key path.
    static func metadataEntryPath(_ keys: [String]) -> String {
        ([metadataPath] + keys.map(escapedEntryKey)).joined(separator: ".")
    }

    // MARK: - Private

    /// Sets one key of an object; ``AnyCodable/null`` removes it. (`AnyCodable` takes a
    /// `nil` literal as `.null`, so assigning `nil` through the subscript would store it.)
    private static func write(_ value: AnyCodable, at key: String, in object: inout [String: AnyCodable]) {
        if value == .null {
            object.removeValue(forKey: key)
        } else {
            object[key] = value
        }
    }

    /// The keys an entry path names, unescaped, or `nil` when it names no entry.
    private static func metadataEntryKeys(of path: String) -> [String]? {
        guard path.hasPrefix(metadataPath + ".") else { return nil }
        let keys = path.dropFirst(metadataPath.count + 1)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.removingPercentEncoding ?? String($0) }
        guard !keys.isEmpty, !keys.contains(where: \.isEmpty) else { return nil }
        switch keys.count {
        case 1: return keys
        case 2 where keys[0] == PenMetadata.woodcaseNamespace: return keys
        default: return nil
        }
    }

    /// A key with `%` and `.` escaped, so it stays one path segment.
    private static func escapedEntryKey(_ key: String) -> String {
        key.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: ".", with: "%2E")
    }
}
