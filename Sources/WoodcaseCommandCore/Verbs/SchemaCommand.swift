//
//  SchemaCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase schema [<type>]` — every property a node type takes, and the shape of each.
///
/// A read verb that reads no file: the vocabulary belongs to the format, not to any one
/// document, so this answers before a `.pen` file exists — which is when an agent most
/// needs it. It is the same answer `woodcase help schema` gives, and the same vocabulary
/// a refused write lists back, because all three come from the decoders.
struct Schema: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Read: every property a node type takes, and the shape of each value.",
        discussion: """
        With no type, the node types the format has and the common.* properties every \
        node takes. With one, that type's own properties: the path `set` accepts, the \
        key the .pen file writes it under, every accepted form with the enumerated \
        values spelled out, and the key tables of anything nested.

        It opens no file, so it answers before a document exists.

          woodcase schema text
        """
    )

    /// The node type to describe. Omitted, the types are listed.
    @Argument(help: ArgumentHelp("A node type, such as `text`. Omit to list them.", valueName: "type"))
    var type: String?

    @OptionGroup var output: OutputOptions

    /// Prints one table, or the list of types.
    ///
    /// - Throws: ``CommandFailure`` when the type is not one the format has.
    func run() throws {
        try print(output.json ? SchemaHelp.json(for: type) : SchemaHelp.text(for: type))
    }
}
