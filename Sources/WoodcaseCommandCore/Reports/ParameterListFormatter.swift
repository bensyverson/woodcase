//
//  ParameterListFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The block `woodcase get` prints for a component's published parameters.
///
/// A component's `common.metadata._props` is its public interface — the names an
/// agent may write and code generation will emit — but until now it was legible only
/// by reading the raw metadata and walking the tree by hand. One row per parameter:
/// the name, the key that means the same thing the long way, the type codegen infers,
/// and a clause where the row needs one.
///
/// ```text
/// props
///   gone   Body/Missing              —      declared path resolves to no node
///   label  Body/Title/kind.content   string
/// ```
enum ParameterListFormatter {
    /// The header the block is announced by, and the word a reader greps for.
    static let header = "props"

    /// The block, or `nil` when the node publishes nothing.
    ///
    /// - Parameter parameters: The node's parameters, as
    ///   ``Woodcase/EditableDocument/parameters(ofComponent:)`` resolved them.
    /// - Returns: The header and one row per parameter, without a trailing newline.
    static func text(_ parameters: [ComponentParameter]) -> String? {
        guard !parameters.isEmpty else { return nil }
        let names = column(parameters.map(\.name))
        let addresses = column(parameters.map { $0.address ?? $0.path })
        let rows = zip(zip(names, addresses), parameters).map { pair, parameter in
            let cells: [String?] = [pair.0, pair.1, parameter.type?.rawValue ?? "—", note(for: parameter)]
            let row = "  " + cells.compactMap(\.self).joined(separator: "  ")
            return String(row.reversed().drop { $0 == " " }.reversed())
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - Private

    /// The clause a row needs, or `nil` when the name means what it looks like.
    private static func note(for parameter: ComponentParameter) -> String? {
        if parameter.collidesWithProperty {
            return "shadowed by this node's own \(parameter.name)"
        }
        guard parameter.property == nil else { return nil }
        return parameter.nodeID == nil
            ? "declared path resolves to no node"
            : "that node has no property a parameter can write"
    }

    /// Cells padded to the width of the widest, so the columns line up.
    private static func column(_ cells: [String]) -> [String] {
        let width = cells.map(\.count).max() ?? 0
        return cells.map { $0.padding(toLength: max(width, $0.count), withPad: " ", startingAt: 0) }
    }
}
