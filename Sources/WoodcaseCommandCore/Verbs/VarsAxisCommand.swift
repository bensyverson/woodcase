//
//  VarsAxisCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// `woodcase vars axis` — the theme axes variables can be pinned to.
///
/// An axis is a name and an ordered list of options (`mode: light, dark`); the first
/// option is the one that is active when nothing pins the axis. `vars set --theme`
/// registers axes on its own, so this exists for declaring a theme up front, before
/// any variable uses it.
struct VarsAxis: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axis",
        abstract: "Write: manage the document's theme axes.",
        subcommands: [VarsAxisAdd.self]
    )
}
