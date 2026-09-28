//
//  NodePropertyCodec+RawKeys.swift
//  Woodcase
//

import Foundation

/// The bridge between the two property vocabularies a .pen file is edited in.
///
/// A node with storage of its own is written in ``NodePropertyCodec``'s dotted paths
/// — `kind.content`, `common.name` — the vocabulary every read prints and `set`
/// accepts. A node **inside a component instance** has no storage: its edit becomes
/// an entry in the instance's `descendants` map, which the format keys by the raw
/// .pen name (`content`, `name`, `fill`). `override` speaks that second vocabulary
/// because the map does.
///
/// Two vocabularies is one more than a caller should have to hold, so anything that
/// can tell which side of the seam a target is on translates rather than refuse.
public extension NodePropertyCodec {
    /// The raw .pen key a property path is stored under.
    ///
    /// A dotted path loses its `common.`/`kind.` prefix and takes the JSON spelling
    /// of its field, so `kind.fills` becomes `fill`. A name that carries no prefix is
    /// already raw and comes back unchanged — which is what makes a caller free to
    /// write either vocabulary.
    ///
    /// - Parameter path: A property path, or a raw .pen key.
    /// - Returns: The key the `descendants` map uses.
    static func rawKey(for path: String) -> String {
        for prefix in [commonPrefix, kindPrefix] where path.hasPrefix(prefix) {
            return jsonKey(for: String(path.dropFirst(prefix.count)))
        }
        return path
    }

    /// Rekeys a whole set of properties for a component instance's override map.
    ///
    /// - Parameter properties: Properties keyed by path, by raw name, or by a mix.
    /// - Returns: The same values, keyed as the `descendants` map keys them.
    static func rawKeyed(_ properties: [String: AnyCodable]) -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]
        for (key, value) in properties {
            result[rawKey(for: key)] = value
        }
        return result
    }
}
