//
//  NodePropertyCodec+ApplicationOrder.swift
//  Woodcase
//

import Foundation

/// The one order a property map's keys are written in.
///
/// A ``EditOperation/SetProperties`` holds its writes in a `Dictionary`, which iterates in
/// hash order — seeded per process — so two replicas, or two runs, walk the same map in
/// different orders. Most keys never meet, but some share storage: `note.fontSize`,
/// `codegen.role` and `common.locked` are stored inside `common.metadata`; a `kind.effects`
/// that names a spread writes `metadata.woodcase.shadowSpread`; `codegen.props.label` is
/// one entry of `codegen.props`. Written in hash order, such a map gave whichever key
/// happened to come last, so peers disagreed.
///
/// Keys are written **broadest storage first**: by how deep the place each key stores
/// into sits (``storageDepth(of:)``), then by path. A whole-object write lands first and
/// the narrower keys beside it refine it — `common.metadata` and then `note.fontSize`
/// means the metadata object with that font size, the reading a caller writing both
/// intends, and the rule ``folding(_:onto:)`` already follows for deep keys. Ties of equal
/// depth fall to the path, so the order is total and the same in every process; which
/// key a refusal names follows it too.
public extension NodePropertyCodec {
    /// A property map's entries in the order they are written.
    ///
    /// - Parameter properties: The writes, keyed by property path.
    /// - Returns: The entries, broadest storage first, ties by path.
    static func applicationOrder(of properties: [String: AnyCodable]) -> [(key: String, value: AnyCodable)] {
        guard properties.count > 1 else { return Array(properties) }
        return properties.map { (rank: (storageDepth(of: $0.key), $0.key), entry: $0) }
            .sorted { $0.rank < $1.rank }
            .map(\.entry)
    }

    /// How many path segments deep the place a key writes sits: `common.metadata` is 2,
    /// `note.fontSize` — stored at `common.metadata.woodcase.fontSize` — is 4.
    ///
    /// A natural path counts at its storage whatever node it is written to, so the order
    /// never depends on the node: a key the node does not take is refused in its turn.
    ///
    /// - Parameter path: A property path.
    /// - Returns: The segment count of the path it stores at.
    internal static func storageDepth(of path: String) -> Int {
        let storage = naturalStoragePath(of: path) ?? PenMetadata.WoodcaseKey(naturalPath: path)?.path ?? path
        return storage.utf8.reduce(1) { $1 == UInt8(ascii: ".") ? $0 + 1 : $0 }
    }
}
