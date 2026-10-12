//
//  AlignedTable.swift
//  Woodcase
//

import Foundation

/// Lays a table of cells out as aligned text: every cell padded to its column's width,
/// columns joined by two spaces, and no line ending in a space, so the bytes are stable.
///
/// The one layout every row listing shares — ``TreeFormatter`` and
/// ``PenNoteBoardFormatter`` — so `tree`, `notes`, `comments` and `prompts` read alike.
///
/// ```swift
/// AlignedTable.text([["name", "id"], ["Card", "Card1"]])
/// // name  id
/// // Card  Card1
/// ```
enum AlignedTable {
    /// Pads every cell to its column's width, never leaving a trailing space.
    ///
    /// - Parameter table: The rows of cells, the header first; a short row is padded.
    /// - Returns: The lines, joined by newlines, with no trailing newline.
    static func text(_ table: [[String]]) -> String {
        let columnCount = table.map(\.count).max() ?? 0
        let widths = (0 ..< columnCount).map { column in
            table.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }

        return table
            .map { row in
                let cells = widths.indices.map { column -> String in
                    let cell = row.indices.contains(column) ? row[column] : ""
                    return cell + String(repeating: " ", count: max(0, widths[column] - cell.count))
                }
                var line = cells.joined(separator: "  ")
                while line.hasSuffix(" ") {
                    line.removeLast()
                }
                return line
            }
            .joined(separator: "\n")
    }
}
