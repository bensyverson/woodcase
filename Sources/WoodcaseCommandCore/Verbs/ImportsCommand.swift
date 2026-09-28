//
//  ImportsCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// `woodcase imports` — the component libraries the document pulls in.
///
/// A read verb by default and two act verbs beneath it, the shape `vars` has over the
/// other table of names the document keeps:
///
/// ```bash
/// woodcase imports design.pen                        # list
/// woodcase imports set design.pen V ./library.pen
/// woodcase imports rm design.pen V                   # refused while a ref uses it
/// ```
///
/// An import aliased `V` puts every identifier the library defines under a `V:` prefix
/// — see <doc:PenImportNamespaces> — so `set` is what makes `V:Bt0aA` mean anything and
/// `rm` is what would stop it meaning anything, which is why the removal is refused
/// while something still reaches into the namespace.
///
/// `imports <file>` with no subcommand lists, for the reason `vars <file>` does: listing
/// is what an agent wants first. The cost is that a `.pen` file named literally `set` or
/// `rm` would be read as a subcommand; name it anything else, or write
/// `imports list ./set`.
struct Imports: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "imports",
        abstract: "Read and write: the component libraries a .pen document imports.",
        subcommands: [ImportsList.self, ImportsSet.self, ImportsRemove.self],
        defaultSubcommand: ImportsList.self
    )
}
