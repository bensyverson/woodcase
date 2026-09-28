//
//  VarsCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// `woodcase vars` — the document's variables and theme axes.
///
/// A read verb by default and a small family of act verbs beneath it:
///
/// ```bash
/// woodcase vars design.pen                                  # list
/// woodcase vars set design.pen brand=#FF6600
/// woodcase vars set design.pen brand=#221100 --theme mode=dark
/// woodcase vars rm design.pen brand                         # refused while referenced
/// woodcase vars axis add design.pen mode=light,dark
/// ```
///
/// `vars <file>` with no subcommand lists, because listing is what an agent wants
/// first and `vars list <file>` would be a word of ceremony on every read. The cost is
/// that a `.pen` file named literally `set`, `rm` or `axis` would be read as a
/// subcommand; name it anything else, or write `vars list ./set`.
struct Vars: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vars",
        abstract: "Read and write: a .pen document's variables and theme axes.",
        subcommands: [VarsList.self, VarsSet.self, VarsRemove.self, VarsAxis.self],
        defaultSubcommand: VarsList.self
    )
}
