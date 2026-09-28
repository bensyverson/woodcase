//
//  ImportsListCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase imports <file>` — a read verb listing the document's library imports.
///
/// ```bash
/// woodcase imports design.pen
/// woodcase imports design.pen --json
/// ```
///
/// The reference count beside each alias is the number of nodes that reach into its
/// namespace, so the answer to "is this library still used?" needs no second command.
/// The `--json` listing carries the document revision, which is what a caller that
/// reads, reasons and then writes should quote.
struct ImportsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Read: the component libraries a .pen file imports.",
        discussion: """
        A read verb: it takes a shared lock and writes nothing. Each row is the alias \
        every identifier of that library is prefixed with, how many nodes reach into \
        the namespace, and the path the alias resolves to — so "is this library still \
        used?" needs no second command.

          woodcase imports list design.pen --json
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints its imports.
    func run() async throws {
        let url = try file.existingFile()
        try await runReportingFailures(editing: url) {
            let listing = try await PenFileTransaction.read(at: url, fonts: .shared) { document in
                ImportFormatter.listing(of: document)
            }.value
            if output.json {
                try print(ImportFormatter.json(listing))
            } else {
                print(ImportFormatter.text(listing, in: url.lastPathComponent))
            }
        }
    }
}
