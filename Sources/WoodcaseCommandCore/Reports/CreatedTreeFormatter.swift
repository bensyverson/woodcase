//
//  CreatedTreeFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders what a mutating verb made: the name → id outline, and the JSON report.
///
/// Every mutating verb answers with this, because the next command needs the ids and
/// a second lookup to learn them is a round trip an agent should not have to pay for.
///
/// ```text
/// Card  ALu8G
///   Title  x9Kqp
/// ```
///
/// Two spaces per level of nesting, two spaces between a name and its id, no trailing
/// newline and no trailing space — the same bytes every time, so a golden test can pin
/// them. A node with no name (only a `cp` of something we did not author can produce
/// one) shows the `#id` marker that addresses it, because that is what a later command
/// must type.
enum CreatedTreeFormatter {
    /// Renders created subtrees as the name → id outline.
    ///
    /// - Parameter roots: The subtrees, in the order they were made.
    /// - Returns: The outline, with no trailing newline.
    static func text(_ roots: [CreatedNode]) -> String {
        roots.flatMap { lines(for: $0, depth: 0) }.joined(separator: "\n")
    }

    /// Renders created subtrees as the JSON report.
    ///
    /// - Parameters:
    ///   - roots: The subtrees, in the order they were made.
    ///   - revision: The document revision the write left behind.
    /// - Returns: The JSON text of a ``Woodcase/CreatedTreeReport``.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ roots: [CreatedNode], revision: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(CreatedTreeReport(created: roots, revision: revision))
        return String(decoding: data, as: UTF8.self)
    }

    /// One node's line and its descendants', outermost first.
    private static func lines(for node: CreatedNode, depth: Int) -> [String] {
        let indent = String(repeating: " ", count: depth * 2)
        let label = node.name ?? NodeAddress.marker(forID: node.id)
        return [indent + label + "  " + node.id]
            + node.children.flatMap { lines(for: $0, depth: depth + 1) }
    }
}
