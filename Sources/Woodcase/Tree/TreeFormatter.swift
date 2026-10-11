//
//  TreeFormatter.swift
//  Woodcase
//

import Foundation

/// Renders ``TreeRow`` values: a terse aligned outline for reading, and the JSON
/// report for parsing.
///
/// ## The text form
///
/// A header row naming the columns, then one line per row, columns padded to the
/// widest cell and joined by two spaces:
///
/// ```text
/// name                   type       rect           id
/// Card                   frame      0,0 200×100    Card1
///   fits                 rectangle  10,10 50×50    Fit01
///   overflows ⚠ partial  rectangle  160,20 80×40   Ovr01
///   #Out01 ⚠ clipped     rectangle  260,120 20×20  Out01
/// ```
///
/// The columns are the name indented by depth, the type, the rect as `x,y w×h`, and
/// the id. The name leads so that a row's depth is its leading indentation: were a
/// variable-width column first, depth would be the gap after it, and a reader that
/// sees runs of spaces rather than aligned columns — an agent — would have to do
/// arithmetic to recover the tree. The id is always last, so it is the last field of
/// a row even when a name or a property value contains spaces.
///
/// Markers ride on the name: a `*` before it marks a reusable component definition, a
/// `+N` after it counts children the listing left out (a depth limit, or an
/// unexpanded instance), `[N runs]` marks a text styled by N runs (<doc:PenRichText>) and
/// `⚠ stale runs` one whose runs were made for other words, and `⚠ partial` /
/// `⚠ clipped` marks a node that falls outside its parent. An unnamed node shows its id marker (`#Out01`), which is also
/// what its address uses. No line ever ends in a space, so the output is byte-stable.
///
/// Requested property columns sit between the rect and the id, labeled by the header.
///
/// ## Coordinates
///
/// The rect column is parent-relative, the layout engine's own convention: only a
/// top-level node's rect is in canvas coordinates. Pass `absolute: true` and the same
/// column carries ``TreeRow/absRect`` instead — document space at every depth — and
/// its header reads `absRect` so the two forms cannot be confused
/// in a saved transcript. The JSON report needs no flag: every row carries both.
public enum TreeFormatter {
    /// What the rows of a listing are, which decides how depth and hidden children
    /// show in the text form.
    public enum Listing: String, Codable, Hashable, Sendable {
        /// A walk of a subtree, in order: depth is the name's leading indentation, and
        /// a row whose children the walk left out counts them (`+N`).
        case outline
        /// Rows picked from anywhere in the document, as `find` picks them: printed
        /// flush, since neighboring rows need not be parent and child, and with no
        /// hidden-children count, since every row hides the rest of its subtree.
        case selection
    }

    /// Renders rows as the aligned text outline.
    ///
    /// - Parameters:
    ///   - rows: The rows to render, in the order they should appear.
    ///   - properties: Property paths to add as columns before the id, in the order
    ///     given.
    ///   - absolute: Whether the rect column carries ``TreeRow/absRect`` — document
    ///     space — rather than ``TreeRow/rect``. The column keeps its name and its
    ///     place either way: one listing is in one coordinate system, so a reader
    ///     never has to work out which number is which.
    ///   - listing: Whether the rows are a walk (``Listing/outline``) or picked from
    ///     anywhere (``Listing/selection``).
    /// - Returns: The header row and the outline, with no trailing newline. Empty for
    ///   no rows.
    public static func text(
        _ rows: [TreeRow],
        properties: [String] = [],
        absolute: Bool = false,
        listing: Listing = .outline
    ) -> String {
        guard !rows.isEmpty else { return "" }

        var table: [[String]] = [["name", "type", absolute ? "absRect" : "rect"] + properties + ["id"]]
        for (index, row) in rows.enumerated() {
            table.append(cells(
                for: row,
                depth: listing == .outline ? row.depth : 0,
                hidesChildren: listing == .outline && hidesChildren(at: index, in: rows),
                properties: properties,
                absolute: absolute
            ))
        }
        return align(table)
    }

    /// Renders rows as the `--json` report: pretty-printed, keys sorted, the document
    /// revision alongside.
    ///
    /// - Parameters:
    ///   - rows: The rows to render.
    ///   - revision: The document revision the rows were read at
    ///     (``EditableDocument/documentRevision``).
    /// - Returns: The JSON text of a ``TreeReport``.
    /// - Throws: Whatever `JSONEncoder` throws for a value that cannot be encoded.
    public static func json(_ rows: [TreeRow], revision: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(TreeReport(revision: revision, rows: rows))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Cells

    /// Whether the row at `index` has children that this listing does not show.
    ///
    /// The listing itself is the evidence: a row's children were shown when the next
    /// row sits one level deeper.
    private static func hidesChildren(at index: Int, in rows: [TreeRow]) -> Bool {
        guard rows[index].childCount > 0 else { return false }
        let next = index + 1
        return next >= rows.count || rows[next].depth <= rows[index].depth
    }

    /// One row's cells, in column order.
    private static func cells(
        for row: TreeRow,
        depth: Int,
        hidesChildren: Bool,
        properties: [String],
        absolute: Bool
    ) -> [String] {
        let indent = String(repeating: " ", count: depth * 2)
        let label = (row.isReusable ? "*" : "") + (row.name ?? NodeAddress.marker(forID: row.id))
        let hidden = hidesChildren ? " +\(row.childCount)" : ""
        let clip = switch row.clip {
        case .none: ""
        case .partial: " ⚠ partial"
        case .full: " ⚠ clipped"
        }
        let spans = row.spans.map { spans in
            spans.isStale ? " ⚠ stale runs" : spans.runs == 1 ? " [1 run]" : " [\(spans.runs) runs]"
        } ?? ""
        let columns = properties.map { path in
            row.properties?[path].map(display) ?? "-"
        }
        return [indent + label + hidden + spans + clip, row.type, rect(absolute ? row.absRect : row.rect)]
            + columns + [row.id]
    }

    /// A rect as `x,y w×h`, or `-` when the layout engine produced none.
    private static func rect(_ rect: PenRect?) -> String {
        guard let rect else { return "-" }
        return "\(number(rect.x)),\(number(rect.y)) \(number(rect.width))×\(number(rect.height))"
    }

    /// A number with no decimal point when it is integral, and two places when it is not.
    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        guard value.rounded() == value, abs(value) < 1e15 else { return String(format: "%.2f", value) }
        return String(Int64(value))
    }

    /// A property value on one line: scalars bare, containers as compact JSON.
    private static func display(_ value: AnyCodable) -> String {
        switch value {
        case .null: "-"
        case let .bool(flag): flag ? "true" : "false"
        case let .int(whole): String(whole)
        case let .double(fraction): number(fraction)
        case let .string(text): oneLine(text)
        case .array, .dictionary: compactJSON(value)
        }
    }

    /// A string with its line breaks and tabs escaped, so a value can never split a row.
    private static func oneLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// A container value as compact JSON with sorted keys.
    private static func compactJSON(_ value: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "?" }
        return oneLine(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Alignment

    /// Pads every cell to its column's width, never leaving a trailing space.
    private static func align(_ table: [[String]]) -> String {
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
                return cells.joined(separator: "  ").trimmedTrailingSpaces
            }
            .joined(separator: "\n")
    }
}

private extension String {
    /// The string with any trailing spaces removed.
    var trimmedTrailingSpaces: String {
        var result = self
        while result.hasSuffix(" ") {
            result.removeLast()
        }
        return result
    }
}
