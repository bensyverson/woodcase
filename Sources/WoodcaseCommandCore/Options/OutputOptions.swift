//
//  OutputOptions.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// The `--json` option group every verb that prints includes.
///
/// The default output is the tersest faithful form — an outline, one row per item —
/// and the stable machine shape is always one flag away. Both go to stdout, and both
/// produce the same bytes in a pipe as in a terminal.
///
/// ```swift
/// @OptionGroup var output: OutputOptions
/// // …
/// print(output.json ? try TreeFormatter.json(rows, revision: rev) : TreeFormatter.text(rows))
/// ```
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the machine-readable JSON form instead of the outline.")
    var json: Bool = false
}
