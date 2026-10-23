//
//  DocumentLinter+ConnectionStyle.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/connectionStyleIgnored`` check.
///
/// A connection's `metadata.woodcase.routing`, `startArrowhead` and `endArrowhead` are drawn
/// only when they hold a spelling Woodcase knows (``PenNode/connectionStyle``); any other
/// value draws as the key's default — straight, no arrowhead. An edit refuses one; a file
/// written by hand or by another tool can still hold it, and is told.
extension DocumentLinter {
    /// One finding for each of a connection's style keys whose value is ignored.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders.
    /// - Returns: The findings, routing first.
    static func connectionStyleIgnored(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case .connection = node.kind, let metadata = node.common.metadata else { return [] }
        let keys: [PenMetadata.WoodcaseKey] = [.routing, .startArrowhead, .endArrowhead]
        return keys.compactMap { key in
            guard let value = metadata[woodcase: key], value != .null, !key.spellings.contains(spelling(of: value))
            else { return nil }
            let fallback = key == .routing ? "straight" : "with no arrowhead there"
            return finding(
                .connectionStyleIgnored, row,
                "has a \(key.propertyPath) of \(EditPlanner.spelling(of: value)), which Woodcase does not draw, "
                    + "so it draws \(fallback). Write one of \(key.spellings.joined(separator: ", "))."
            )
        }
    }

    /// A value's text when it is a string, so it can be checked against a key's spellings.
    private static func spelling(of value: AnyCodable) -> String {
        guard case let .string(text) = value else { return "" }
        return text
    }
}
