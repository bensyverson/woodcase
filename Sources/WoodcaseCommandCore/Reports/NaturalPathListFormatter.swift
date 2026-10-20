//
//  NaturalPathListFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The block `woodcase get` prints for the Woodcase-owned values a node sets, at the
/// natural paths a caller reads and writes them at.
///
/// The node JSON below it is the file's own, which keeps these values in
/// `metadata.woodcase`; this block is how `get` names them the way `set` writes them
/// (rule 1 of `project/2026-10-20-natural-paths-for-woodcase-properties.md`).
///
/// ```text
/// woodcase-owned — stored in metadata.woodcase; set these paths
///   common.locked     true
///   kind.strokeDash   [8,4]
/// ```
enum NaturalPathListFormatter {
    /// The header the block is announced by, and the word a reader greps for.
    static let header = "woodcase-owned — stored in metadata.woodcase; set these paths"

    /// The block, or `nil` when the node sets none.
    ///
    /// - Parameter values: The values by natural path (``Woodcase/NodeReport/properties``).
    /// - Returns: The header and one row per path, sorted, without a trailing newline.
    static func text(_ values: [String: AnyCodable]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        let paths = values.keys.sorted()
        let width = paths.map(\.count).max() ?? 0
        let rows = paths.map { path in
            "  \(path.padding(toLength: width, withPad: " ", startingAt: 0))  \(compact(values[path] ?? .null))"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// One value as compact JSON, keys sorted, so the row is one line.
    private static func compact(_ value: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return text
    }
}
