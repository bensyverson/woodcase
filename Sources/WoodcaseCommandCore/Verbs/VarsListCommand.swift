//
//  VarsListCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase vars <file>` — a read verb listing variables and theme axes.
///
/// ```bash
/// woodcase vars design.pen
/// woodcase vars design.pen --json
/// ```
///
/// The reference count beside each variable is the number of nodes that bind a
/// property to it, so the answer to "is this still used?" needs no second command.
/// The listing carries the document revision, which is what a caller that reads,
/// reasons and then writes should quote.
struct VarsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Read: the variables and theme axes a .pen file defines.",
        discussion: """
        A read verb: it takes a shared lock and writes nothing. Each row is the \
        variable's name, its declared type, the value it resolves to under each theme, \
        and how many nodes bind a property to it — so "is this still used?" needs no \
        second command. The header carries the document revision.

          woodcase vars list design.pen --json
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints its variables and axes.
    func run() async throws {
        let url = try file.existingFile()
        try await runReportingFailures(editing: url) {
            let listing = try await PenFileTransaction.read(at: url, fonts: .shared) { document in
                VariableFormatter.listing(of: document)
            }.value
            if output.json {
                try print(VariableFormatter.json(listing))
            } else {
                print(VariableFormatter.text(listing, in: url.lastPathComponent))
            }
        }
    }
}
