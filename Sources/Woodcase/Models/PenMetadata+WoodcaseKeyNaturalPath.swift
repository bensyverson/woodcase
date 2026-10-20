//
//  PenMetadata+WoodcaseKeyNaturalPath.swift
//  Woodcase
//

import Foundation

/// The natural path a Woodcase key is read and written at, beside where it is stored.
///
/// A key that stands in for a property Pen's format lacks is written the way a caller
/// would guess it — `kind.blendMode` — and Woodcase stores it in `metadata.woodcase`, which
/// Pen keeps. ``NodePropertyCodec`` converts between the two, so no reader or writer
/// spells the storage path (Ben's ruling of 2026-10-20;
/// `project/2026-10-20-natural-paths-for-woodcase-properties.md`).
///
/// This is the one table of that mapping: a key's ``naturalPath``. Which node types take
/// the path is the codec's vocabulary (``PropertyDiff/allKindKeys(_:)-(PenNode.NodeType)``),
/// as for every other `kind.*` path.
public extension PenMetadata.WoodcaseKey {
    /// The property path a caller reads and writes this key at, or `nil` for a key read and
    /// written at its storage path (``path``).
    ///
    /// Only ``blendMode`` has one so far: a node's blend mode was a `kind.*` property
    /// before it moved into metadata, and `kind.blendMode` stayed its path.
    var naturalPath: String? {
        switch self {
        case .blendMode: "kind.blendMode"
        default: nil
        }
    }

    /// The key a natural path stands for.
    ///
    /// - Parameter naturalPath: A property path, such as `kind.blendMode`.
    /// - Returns: `nil` when the path is no key's ``naturalPath``.
    init?(naturalPath: String) {
        guard let key = Self.byNaturalPath[naturalPath] else { return nil }
        self = key
    }

    /// Every key with a natural path, by that path.
    private static let byNaturalPath: [String: Self] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { key in key.naturalPath.map { ($0, key) } }
    )
}
