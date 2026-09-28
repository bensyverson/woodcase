//
//  SeparatorRemedy.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

/// The sentence a dash-prefixed variable name gets instead of `Missing expected
/// argument '<name=value>'`.
///
/// Every design-token file names its variables `--accent`, `--surface`, `--warn`, and
/// `woodcase vars set design.pen --accent=#e0561a` puts that name where an option goes.
/// ArgumentParser's answer is accurate and teaches nothing: two agents in round two of
/// the host trial hit it, one renamed its whole token set to get past it, and the other
/// took three tries. The rule they needed is one sentence — a name that starts with a
/// dash needs a bare `--` before it — and it is the same sentence `vars set --help` and
/// `woodcase help design` carry, so wherever a caller meets it first, it reads alike.
///
/// The remedy is never *applied*: rewriting the vector so `--accent=…` "just works"
/// would make a mistyped option indistinguishable from a token name, and the caller
/// would be told nothing at all. This says the rule and prints the line to run.
///
/// ## How a name is told from an option
///
/// By asking the parser, not by keeping a table of `vars set`'s options — a table would
/// drift the first time one was added. A candidate `--name=value` is a variable name
/// only when a `vars set` line that is otherwise complete *still* fails with it
/// present: `--type=color` parses beside an assignment and is an option;
/// `--accent=#e0561a` does not and is a name.
enum SeparatorRemedy {
    /// The example every place that states the rule shows.
    ///
    /// One string, so `vars set --help`, `woodcase help design` and this refusal cannot
    /// come to show three different commands.
    static let example = "woodcase vars set f.pen -- --accent=#e0561a"

    /// The rule, as the two help texts state it.
    static let rule = """
    A variable name that starts with a dash needs a bare -- before it, or the parser \
    reads it as an option: everything after the -- is an operand.
    """

    /// The sentence to print in place of the parser's, or `nil` to leave it alone.
    ///
    /// - Parameter arguments: The command line as the parser saw it, without the
    ///   program name.
    /// - Returns: One line for standard error, naming what was read as an option, the
    ///   rule, and the repaired command — or `nil` when the failure is not this one.
    static func message(for arguments: [String]) -> String? {
        guard arguments.starts(with: ["vars", "set"]), !arguments.contains("--") else { return nil }
        let names = arguments.filter(isName)
        guard let first = names.first else { return nil }

        var repaired = arguments.filter { !isName($0) }
        repaired.append("--")
        repaired.append(contentsOf: names)
        let subject = names.count == 1
            ? "\(first) was read as an option, not as the variable \(name(of: first))"
            : "\(names.joined(separator: " and ")) were read as options, not as variable names"
        return "\(subject). \(rule) Run `woodcase \(repaired.joined(separator: " "))`."
    }

    // MARK: - Private

    /// Whether an argument is a variable name `vars set` could only read after a `--`.
    ///
    /// - Parameter argument: One token of the command line.
    /// - Returns: `true` when it is shaped `--name=value` and `vars set` does not
    ///   accept `--name` as an option of its own.
    private static func isName(_ argument: String) -> Bool {
        guard argument.hasPrefix("--"), argument.count > 2 else { return false }
        let body = argument.dropFirst(2)
        guard let equals = body.firstIndex(of: "="), equals != body.startIndex else { return false }
        // The probe is a complete `vars set` line but for this token. If it parses, the
        // token is one of the verb's own options and the caller's fault lies elsewhere.
        let probe = ["vars", "set", "probe.pen", "probe=1", argument]
        return (try? WoodcaseCommand.parseAsRoot(probe)) == nil
    }

    /// The variable name a `--name=value` token declares.
    private static func name(of argument: String) -> String {
        String(argument.prefix { $0 != "=" })
    }
}
