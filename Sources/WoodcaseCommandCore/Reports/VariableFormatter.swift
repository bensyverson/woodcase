//
//  VariableFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders a document's variables and theme axes, as rows and as JSON.
///
/// One row per variable — name, type, how many things reference it, and its value —
/// with a themed variable's variants on indented rows beneath it, because a variable
/// with four theme variants is four facts, not one:
///
/// ```text
/// variables
///   bgColor   color   1 ref
///     mode=light  #FFFFFF
///     mode=dark   #1A1A1A
///     *           #F0F0F0
///   headline  string  2 refs  Breaking News
///
/// axes
///   mode  light, dark
/// ```
///
/// `*` is the variant with no `theme`: the value the resolver falls back to. Variants
/// keep the order the file stores them in, since that is the order the resolver reads
/// them in. Every mutating `vars` verb prints its result through the same row, so what
/// a write answers with is what the next `vars` will show.
enum VariableFormatter {
    /// Everything `vars` reports about a document.
    struct Listing: Friendly {
        /// Creates a listing.
        ///
        /// - Parameters:
        ///   - variables: One row per variable, sorted by name.
        ///   - axes: One row per theme axis, sorted by name.
        ///   - revision: The document revision this was read at.
        init(variables: [Row], axes: [Axis], revision: String) {
            self.variables = variables
            self.axes = axes
            self.revision = revision
        }

        /// One row per variable, sorted by name.
        let variables: [Row]

        /// One row per theme axis, sorted by name.
        let axes: [Axis]

        /// The document revision this was read at, so a caller that reasons and then
        /// writes can say what it was looking at.
        let revision: String
    }

    /// One variable.
    struct Row: Friendly {
        /// Creates a row.
        ///
        /// - Parameters:
        ///   - name: The variable's name, without the `$`.
        ///   - type: The type it declares.
        ///   - references: How many things mention it.
        ///   - values: Its variants, in the order the file stores them. A variable with
        ///     one plain value has a single variant whose `theme` is `nil`.
        init(name: String, type: PenVariableType, references: References, values: [PenThemedValue]) {
            self.name = name
            self.type = type
            self.references = references
            self.values = values
        }

        /// The variable's name, without the `$`.
        let name: String

        /// The type it declares.
        let type: PenVariableType

        /// How many things mention it.
        let references: References

        /// Its variants, in the order the file stores them.
        let values: [PenThemedValue]
    }

    /// How many things mention a variable.
    struct References: Friendly {
        /// Creates a count.
        ///
        /// - Parameter references: What the document's walk found, or `nil` for a
        ///   variable nothing mentions.
        init(_ references: VariableReferences?) {
            nodes = references?.nodeIDs.count ?? 0
            variables = references?.variableNames.count ?? 0
        }

        /// How many nodes bind a property to it.
        let nodes: Int

        /// How many other variables resolve through it.
        let variables: Int
    }

    /// One theme axis.
    struct Axis: Friendly {
        /// Creates an axis row.
        ///
        /// - Parameters:
        ///   - name: The axis name.
        ///   - options: Its options, in the order the file stores them — the first is
        ///     the one that is active when nothing pins the axis.
        init(name: String, options: [String]) {
            self.name = name
            self.options = options
        }

        /// The axis name.
        let name: String

        /// Its options, in file order.
        let options: [String]
    }

    // MARK: - Reading a document

    /// Everything `vars` reports about a document.
    ///
    /// - Parameter document: The document to read.
    /// - Returns: Its variables, its axes and its revision.
    static func listing(of document: EditableDocument) -> Listing {
        let index = document.variableReferences()
        let variables = (document.variables ?? [:])
            .sorted { $0.key < $1.key }
            .map { name, variable in
                Row(
                    name: name,
                    type: variable.type,
                    references: References(index[name]),
                    values: variants(of: variable.value)
                )
            }
        return Listing(variables: variables, axes: axes(of: document), revision: document.documentRevision)
    }

    /// One variable's row, read from the document as it now stands.
    ///
    /// - Parameters:
    ///   - name: The variable to describe.
    ///   - document: The document holding it.
    /// - Returns: The row, or `nil` if the document does not define that name.
    static func row(for name: String, in document: EditableDocument) -> Row? {
        rows(for: [name], in: document).first
    }

    /// Several variables' rows, over **one** walk of the document.
    ///
    /// ``EditableDocument/variableReferences()`` re-encodes every node, so asking it
    /// once per name turns a seventeen-token write into seventeen walks. `vars list`
    /// already reads the whole index once; this is the same read, narrowed to the names
    /// a write touched.
    ///
    /// - Parameters:
    ///   - names: The variables to describe, in the order they should be reported.
    ///   - document: The document holding them.
    /// - Returns: One row per name the document defines, in the order given. A name the
    ///   document does not define is absent rather than empty.
    static func rows(for names: [String], in document: EditableDocument) -> [Row] {
        let index = document.variableReferences()
        return names.compactMap { name in
            guard let variable = document.variables?[name] else { return nil }
            return Row(
                name: name,
                type: variable.type,
                references: References(index[name]),
                values: variants(of: variable.value)
            )
        }
    }

    /// A document's theme axes, sorted by name.
    ///
    /// - Parameter document: The document to read.
    /// - Returns: One row per axis.
    static func axes(of document: EditableDocument) -> [Axis] {
        (document.themes ?? [:])
            .sorted { $0.key < $1.key }
            .map { Axis(name: $0.key, options: $0.value) }
    }

    // MARK: - Rendering

    /// The whole listing as rows.
    ///
    /// - Parameters:
    ///   - listing: What to render.
    ///   - fileName: The file's name, for the sentence a document with neither
    ///     variables nor axes gets — an empty listing is a true answer, not an error.
    /// - Returns: The text, with no trailing newline.
    static func text(_ listing: Listing, in fileName: String) -> String {
        var blocks: [String] = []
        if !listing.variables.isEmpty {
            blocks.append((["variables"] + lines(for: listing.variables)).joined(separator: "\n"))
        }
        if !listing.axes.isEmpty {
            blocks.append((["axes"] + lines(for: listing.axes)).joined(separator: "\n"))
        }
        guard !blocks.isEmpty else { return "No variables or theme axes in \(fileName)." }
        return blocks.joined(separator: "\n\n")
    }

    /// Variable rows, and one indented row per variant of a themed variable.
    ///
    /// - Parameter rows: The variables to render.
    /// - Returns: One line per row plus one per variant, indented two and four spaces.
    static func lines(for rows: [Row]) -> [String] {
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let typeWidth = rows.map(\.type.rawValue.count).max() ?? 0
        let referenceWidth = rows.map { text(for: $0.references).count }.max() ?? 0
        return rows.flatMap { row -> [String] in
            var head = "  " + padded(row.name, to: nameWidth)
                + "  " + padded(row.type.rawValue, to: typeWidth)
                + "  " + padded(text(for: row.references), to: referenceWidth)
            if let plain = row.values.first, row.values.count == 1, plain.theme == nil {
                return [trimmed(head + "  " + display(plain.value))]
            }
            head = trimmed(head)
            let pinWidth = row.values.map { pin(row: $0.theme).count }.max() ?? 0
            return [head] + row.values.map { variant in
                "    " + padded(pin(row: variant.theme), to: pinWidth) + "  " + display(variant.value)
            }
        }
    }

    /// Axis rows.
    ///
    /// - Parameter axes: The axes to render.
    /// - Returns: One line per axis, indented two spaces.
    static func lines(for axes: [Axis]) -> [String] {
        let width = axes.map(\.name.count).max() ?? 0
        return axes.map { "  " + padded($0.name, to: width) + "  " + $0.options.joined(separator: ", ") }
    }

    /// Anything `vars` answers with, as JSON.
    ///
    /// - Parameter value: The report to encode.
    /// - Returns: Pretty-printed JSON with sorted keys, so a golden test can pin it.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    /// A value as it appears in a row.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: Its plainest readable form — a string unquoted, a whole number
    ///   without a decimal point.
    static func display(_ value: AnyCodable) -> String {
        switch value {
        case .null: "null"
        case let .bool(flag): flag ? "true" : "false"
        case let .int(number): String(number)
        case let .double(number): Int(exactly: number).map(String.init) ?? String(number)
        case let .string(text): text
        case let .array(items): "[" + items.map(display).joined(separator: ", ") + "]"
        case let .dictionary(entries):
            "{" + entries.keys.sorted().map { "\($0): \(display(entries[$0] ?? .null))" }
                .joined(separator: ", ") + "}"
        }
    }

    /// A variant's theme pin as it appears in a row.
    ///
    /// - Parameter theme: The axes and options this variant is for, or `nil` for the
    ///   default.
    /// - Returns: `axis=option` pairs sorted by axis and joined by commas, or `*`.
    static func pin(row theme: [String: String]?) -> String {
        guard let theme, !theme.isEmpty else { return "*" }
        return theme.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// A reference count as it appears in a row.
    ///
    /// - Parameter references: The counts.
    /// - Returns: `"2 refs"`, and `"2 refs, 1 var"` when other variables resolve
    ///   through it — the second number matters because removing the variable breaks
    ///   those too.
    static func text(for references: References) -> String {
        var text = "\(references.nodes) " + (references.nodes == 1 ? "ref" : "refs")
        if references.variables > 0 {
            text += ", \(references.variables) " + (references.variables == 1 ? "var" : "vars")
        }
        return text
    }

    // MARK: - Private

    /// A variable's value as the list of variants a row shows.
    private static func variants(of value: PenVariableValue) -> [PenThemedValue] {
        switch value {
        case let .simple(plain): [PenThemedValue(value: plain, theme: nil)]
        case let .themed(variants): variants
        }
    }

    private static func padded(_ text: String, to width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }

    /// A line with no trailing spaces, so the same row is the same bytes whether or not
    /// a later column happened to be empty.
    private static func trimmed(_ line: String) -> String {
        var line = line
        while line.hasSuffix(" ") {
            line.removeLast()
        }
        return line
    }
}
