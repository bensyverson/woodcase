//
//  SchemaTableFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Lays ``PenSchemaTable`` out as columns, and encodes it as JSON.
///
/// Three columns, because three is what a caller has to hold: the path `set` takes, the
/// key the file writes, and every form the value may have. A fourth column for the
/// `$variable` type was tried and dropped — it pushed the widest rows past a hundred
/// columns, and `$number` reads perfectly well as one more alternative in the union,
/// which is exactly how a caller types it.
enum SchemaTableFormatter {
    /// The header the columns are titled with.
    private static let headings = (path: "path", key: ".pen key", value: "value")

    /// A table's rows, aligned, with a heading line.
    ///
    /// - Parameter table: The table to lay out.
    /// - Returns: The heading and one indented line per property.
    static func rows(of table: PenSchemaTable) -> String {
        let pathWidth = max(headings.path.count, table.properties.map(\.path.count).max() ?? 0)
        let keyWidth = max(headings.key.count, table.properties.map(\.key.column.count).max() ?? 0)
        let heading = line(headings.path, headings.key, headings.value, pathWidth, keyWidth)
        let body = table.properties.map { line($0.path, $0.key.column, $0.value, pathWidth, keyWidth) }
        return ([heading] + body).joined(separator: "\n")
    }

    /// Every nested key table, each with its variants and their keys.
    ///
    /// - Parameter shapes: The shapes to lay out, in the order they should read.
    /// - Returns: One block per shape, separated by a blank line.
    static func nested(_ shapes: [PenNestedShape]) -> String {
        shapes.map(block(for:)).joined(separator: "\n\n")
    }

    // MARK: - JSON

    /// Encodes a schema payload the way every other `--json` output is encoded.
    ///
    /// - Parameter value: The payload to encode.
    /// - Returns: Pretty-printed JSON with sorted keys.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    // MARK: - Private

    /// One nested shape: its name, what it is for, and each variant's keys.
    private static func block(for shape: PenNestedShape) -> String {
        var lines = ["  \(shape.name) — \(shape.summary)"]
        let keyWidth = shape.variants
            .flatMap { $0.fields.map { $0.key.count + ($0.isRequired ? 1 : 0) } }
            .max() ?? 0
        for variant in shape.variants {
            if let spelling = variant.spelling, let discriminator = shape.discriminator {
                lines.append("    \"\(discriminator)\": \"\(spelling)\"")
            }
            for field in variant.fields {
                let key = field.key + (field.isRequired ? "*" : "")
                lines.append("      \(key.padding(toLength: keyWidth, withPad: " ", startingAt: 0))  \(field.value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// One aligned row of the three columns.
    private static func line(
        _ path: String,
        _ key: String,
        _ value: String,
        _ pathWidth: Int,
        _ keyWidth: Int
    ) -> String {
        let paddedPath = path.padding(toLength: pathWidth, withPad: " ", startingAt: 0)
        let paddedKey = key.padding(toLength: keyWidth, withPad: " ", startingAt: 0)
        return "  \(paddedPath)  \(paddedKey)  \(value)"
    }
}
