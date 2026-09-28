//
//  PositionOption.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// The `--at <n>` option group the verbs that place a node include.
///
/// The position among the destination parent's children, counting from 0. Omitting
/// it appends, which is what an agent wants most of the time; `--at 0` puts the node
/// first. An index past the end is refused with a message saying what the range is,
/// rather than silently appending — a silent clamp is how a layout ends up subtly
/// wrong with nothing to read.
///
/// ```bash
/// woodcase add design.pen Card -F badge.json --at 0
/// ```
struct PositionOption: ParsableArguments {
    @Option(
        name: .customLong("at"),
        help: ArgumentHelp(
            "Position among the parent's children, counting from 0. Omit to append.",
            valueName: "n"
        )
    )
    var at: Int?
}
