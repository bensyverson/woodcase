//
//  PenVariableType+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--type color` on the command line.
///
/// The raw values are the schema's own type names, so what the flag takes is what the
/// `.pen` file stores.
extension PenVariableType: ExpressibleByArgument {
    /// The values `--help` offers.
    ///
    /// Spelled out rather than derived, because ``PenVariableType`` is not
    /// `CaseIterable` and making it so is a library change this verb does not need. A
    /// new case would still be caught: ``VariableTyping/value(of:as:)`` switches over
    /// the type exhaustively, so the compiler stops here first.
    public static var allValueStrings: [String] {
        ["boolean", "color", "number", "string"]
    }
}
