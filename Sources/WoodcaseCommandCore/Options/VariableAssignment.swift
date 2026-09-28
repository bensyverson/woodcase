//
//  VariableAssignment.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A `name=value` argument: the one assignment shape the CLI takes.
///
/// `woodcase vars set design.pen brand=#FF6600` and
/// `woodcase vars axis add design.pen mode=light,dark` are the same grammar — a name,
/// an equals sign, and everything after it. `axis add` reads the value through
/// ``options`` as a comma-separated list; `set` takes it whole, so a value may itself
/// contain equals signs and commas.
///
/// Parsing fails only on the *shape*, which is a fact about the invocation: no equals
/// sign, an empty name, or a name carrying a `:` (the 2.17 schema's key pattern for a
/// variable name and a theme axis is `[^:]+`). ArgumentParser turns that into a usage
/// exit, which is right. Whether the value suits the variable's type is a question for
/// ``VariableTyping``, asked when the verb runs.
struct VariableAssignment: ExpressibleByArgument, Friendly, CustomStringConvertible {
    /// Splits an argument on its first equals sign.
    ///
    /// - Parameter argument: The text as typed, `name=value`.
    init?(argument: String) {
        guard let equals = argument.firstIndex(of: "=") else { return nil }
        let name = String(argument[argument.startIndex ..< equals])
        guard !name.isEmpty, !name.contains(":") else { return nil }
        self.name = name
        literal = String(argument[argument.index(after: equals)...])
    }

    /// The name on the left of the equals sign.
    let name: String

    /// Everything on the right of the first equals sign, verbatim.
    let literal: String

    /// The value read as a comma-separated list, for `vars axis add`.
    ///
    /// Blank entries are dropped, so `mode=light,,dark` and `mode=light, dark` both
    /// give `["light", "dark"]`.
    var options: [String] {
        literal
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The assignment as typed.
    var description: String {
        "\(name)=\(literal)"
    }
}
