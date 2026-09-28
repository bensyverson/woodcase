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
/// One line per row, columns padded to the widest cell and joined by two spaces:
///
/// ```text
/// frame      Card         0,0 200×100               Card1
/// rectangle    fits       10,10 50×50               Fit01
/// rectangle    overflows  160,20 80×40   ⚠ partial  Ovr01
/// rectangle    #Out01     260,120 20×20  ⚠ clipped  Out01
/// ```
///
/// The columns are the type, the name indented by depth, the rect as `x,y w×h`, the
/// clip flag and the id — around 55 characters for a typical row. Two markers ride
/// along: a `*` before the type marks a reusable component definition, and a `+N`
/// after the name counts children the listing left out (a depth limit, or an
/// unexpanded instance). An unnamed node shows its id marker (`#Out01`) in the name
/// column, which is also what its address uses. A column that is empty on every row
/// is dropped, and no line ever ends in a space, so the output is byte-stable.
///
/// Requested property columns follow the id, and — only then — a header line names
/// every column, because an unlabelled value column teaches nothing.
///
/// ## Coordinates
///
/// The rect column is parent-relative, the layout engine's own convention: only a
/// top-level node's rect is in canvas coordinates. Pass `absolute: true` and the same
/// column carries ``TreeRow/absRect`` instead — document space at every depth — and
/// its header, when there is one, reads `absRect` so the two forms cannot be confused
/// in a saved transcript. The JSON report needs no flag: every row carries both.
public enum TreeFormatter {
    /// Renders rows as the aligned text outline.
    ///
    /// - Parameters:
    ///   - rows: The rows to render, in the order they should appear.
    ///   - properties: Property paths to add as columns, in the order given. When
    ///     this is non-empty a header line naming the columns is emitted first.
    ///   - absolute: Whether the rect column carries ``TreeRow/absRect`` — document
    ///     space — rather than ``TreeRow/rect``. The column keeps its name and its
    ///     place either way: one listing is in one coordinate system, so a reader
    ///     never has to work out which number is which.
    /// - Returns: The outline, with no trailing newline. Empty for no rows.
    public static func text(
        _ rows: [TreeRow],
        properties: [String] = [],
        absolute: Bool = false
    ) -> String {
        guard !rows.isEmpty else { return "" }

        var table: [[String]] = []
        if !properties.isEmpty {
            table.append(["type", "name", absolute ? "absRect" : "rect", "clip", "id"] + properties)
        }
        for (index, row) in rows.enumerated() {
            table.append(cells(
                for: row,
                hidesChildren: hidesChildren(at: index, in: rows),
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
        hidesChildren: Bool,
        properties: [String],
        absolute: Bool
    ) -> [String] {
        let type = (row.isReusable ? "*" : "") + row.type
        let indent = String(repeating: " ", count: row.depth * 2)
        let label = row.name ?? NodeAddress.marker(forID: row.id)
        let name = indent + label + (hidesChildren ? " +\(row.childCount)" : "")
        let clip = switch row.clip {
        case .none: ""
        case .partial: "⚠ partial"
        case .full: "⚠ clipped"
        }
        let columns = properties.map { path in
            row.properties?[path].map(display) ?? "-"
        }
        return [type, name, rect(absolute ? row.absRect : row.rect), clip, row.id] + columns
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

    /// Pads every cell to its column's width, dropping columns that are empty
    /// throughout and never leaving a trailing space.
    private static func align(_ table: [[String]]) -> String {
        let columnCount = table.map(\.count).max() ?? 0
        let widths = (0 ..< columnCount).map { column in
            table.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }
        let kept = widths.indices.filter { widths[$0] > 0 }

        return table
            .map { row in
                let cells = kept.map { column -> String in
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
