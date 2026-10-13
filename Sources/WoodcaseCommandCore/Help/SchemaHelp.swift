//
//  SchemaHelp.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `woodcase schema` and `woodcase help schema` print, in both dialects.
///
/// The verb and the topic are the same answer reached two ways — an agent that has read
/// the primer types `help schema`, one that has read a refusal types `schema text` — so
/// neither renders anything of its own. Both come here, and a test asserts their bytes
/// are identical.
///
/// Nothing in this file describes the format. Every row comes from ``PenSchema``, which
/// reads the decoders; this file only decides where the columns line up.
enum SchemaHelp {
    // MARK: - Text

    /// The whole vocabulary, or one node type's.
    ///
    /// - Parameter typeName: A node type name, or `nil` for the list of types and the
    ///   shared properties.
    /// - Returns: The table, ready to print.
    /// - Throws: ``CommandFailure`` when `typeName` names no type in the format.
    static func text(for typeName: String?) throws -> String {
        guard let typeName else { return overviewText() }
        if typeName == PenPostIt.typeValue { return postItText() }
        let type = try resolve(typeName)
        return typeText(type)
    }

    /// The machine-readable form of the same tables.
    ///
    /// - Parameter typeName: A node type name, or `nil` for the overview.
    /// - Returns: The JSON object, ready to print.
    /// - Throws: ``CommandFailure`` when `typeName` names no type, or the encoder's error.
    static func json(for typeName: String?) throws -> String {
        guard let typeName else {
            return try SchemaTableFormatter.json(SchemaOverviewReport())
        }
        if typeName == PenPostIt.typeValue {
            return try SchemaTableFormatter.json(SchemaPostItReport())
        }
        let type = try resolve(typeName)
        return try SchemaTableFormatter.json(SchemaTypeReport(type: type))
    }

    /// The node type a caller named.
    ///
    /// The sentence is ``Woodcase/SchemaTypeNotFound``'s, so `woodcase schema textbox`
    /// and a script's `doc.schema('textbox')` refuse in the same words; only the exit
    /// code is this layer's.
    ///
    /// - Parameter name: The word after `schema`.
    /// - Returns: The type it names.
    /// - Throws: ``CommandFailure`` listing every type, because a caller who guessed
    ///   `textbox` needs the sixteen real names more than a restatement of the guess.
    static func resolve(_ name: String) throws -> PenNode.NodeType {
        do {
            return try SchemaLookup.type(named: name)
        } catch let error as SchemaTypeNotFound {
            throw CommandFailure(message: error.message, exitCode: .usage)
        }
    }

    // MARK: - The overview

    /// The list of node types, then the shared properties, then the root's own tables.
    private static func overviewText() -> String {
        let width = PenNode.NodeType.allCases.map(\.rawValue.count).max() ?? 0
        let types = PenNode.NodeType.allCases.map { type in
            "  \(type.rawValue.padding(toLength: width, withPad: " ", startingAt: 0))  \(type.summary)"
        }
        return """
        NODE TYPES — `woodcase schema <type>` prints one type's properties

        \(types.joined(separator: "\n"))

        COMMON PROPERTIES — \(PenSchema.common.summary)

        \(SchemaTableFormatter.rows(of: PenSchema.common))

        \(SchemaTableFormatter.constraints(of: PenSchema.common) ?? "")

        \(SchemaTableFormatter.defaults(of: PenSchema.common) ?? "")

        DOCUMENT ROOT — keys beside "children"; a key marked * is required

        \(SchemaTableFormatter.nested(PenSchema.rootShapes))

        POST-IT CONVENTION — `woodcase schema \(PenPostIt.typeValue)` prints the keys a note carries \
        under common.metadata.woodcase

        \(legend)
        """
    }

    // MARK: - One type

    /// One node type's own properties, the shapes they nest, and where the rest is.
    private static func typeText(_ type: PenNode.NodeType) -> String {
        let table = PenSchema.table(for: type)
        var sections = [
            "\(type.rawValue) — \(table.summary)",
            SchemaTableFormatter.rows(of: table),
        ]
        if let constraints = SchemaTableFormatter.constraints(of: table) {
            sections.append(constraints)
        }
        if let defaults = SchemaTableFormatter.defaults(of: table) {
            sections.append(defaults)
        }
        if !table.nested.isEmpty {
            sections.append("NESTED SHAPES\n\n" + SchemaTableFormatter.nested(table.nested))
        }
        sections.append("""
        A \(type.rawValue) also takes the \(PenSchema.common.properties.count) common.* properties every \
        node has — `woodcase schema` lists them.

        \(legend)
        """)
        return sections.joined(separator: "\n\n")
    }

    // MARK: - The post-it convention

    /// The post-it metadata keys, what each holds and the spellings the typed ones take.
    ///
    /// Not a node type: a convention over `common.metadata`, so it has no `kind.*` rows
    /// and no legend, only the key table ``SchemaPostItReport`` carries.
    private static func postItText() -> String {
        let report = SchemaPostItReport()
        let width = report.keys.map(\.key.count).max() ?? 0
        let rows = report.keys.map { key in
            let path = key.key.padding(toLength: width, withPad: " ", startingAt: 0)
            let spellings = key.spellings.isEmpty ? key.takes : key.spellings.joined(separator: " | ")
            return "  \(path)  \(spellings) — \(key.summary)"
        }
        return """
        \(report.type) — \(report.summary)

        \(rows.joined(separator: "\n"))

        Write one key with a deep key: woodcase set <file> <note> common.metadata.woodcase.tint=#A5D6A7
        A note written before the namespace keeps bare keys beside metadata.type "\(PenPostIt.typeValue)"; \
        they are still read, and `woodcase migrate` moves them in.
        """
    }

    // MARK: - The legend

    /// The conventions every table uses, said once at the foot of each, wrapped by hand
    /// so the same bytes reach a pipe and a narrow terminal.
    private static let legend = """
    A value written "$name" is a reference to a variable, and \
    \(PenVariableType.allCases.map { "$\($0.rawValue)" }.joined(separator: ", "))
    say which type of variable that property takes. A string property that must \
    itself hold a $ escapes it: \\$name stores the literal string $name rather \
    than resolving it, anywhere in the string. \
    \(PenValueForm.StringRole.blendMode.signature) and \
    \(PenValueForm.StringRole.svgPathData.signature) are strings in a fixed form; \
    \(PenValueForm.StringRole.fontFamily.signature) is a family name, \
    \(PenValueForm.StringRole.fontWeight.signature) a CSS weight ("700") or a keyword \
    (bold), and \(PenValueForm.StringRole.fontStyle.signature) is normal or italic.
    Every length is in points, with one exception: kind.lineHeight is a multiple of \
    fontSize, so 1.4 is 140% leading and 21 is a line box fourteen times too tall.
    A key marked * is required; `null` clears a property.
    """
}
