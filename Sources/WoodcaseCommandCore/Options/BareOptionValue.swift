//
//  BareOptionValue.swift
//  WoodcaseCommandCore
//

import Foundation

/// The options whose value may be left off, and what stands in when it is.
///
/// `ArgumentParser` has no optional-valued option: an option either takes a value or is
/// a flag, and `--props` written with nothing after it fails during parsing —
/// `Missing value for '--props <props>'` — before any verb has a chance to default it.
/// That is the wrong answer for a widening flag. `--props` says *show me more*; which
/// columns is a detail the caller may not have an opinion about, and every other read in
/// this CLI defaults sensibly.
///
/// So the value is filled in at the one place the command line is still a plain array:
/// the entry point, before the parser runs. This is deliberately a table of one. An
/// option belongs here only when writing it bare is a request the verb can answer, and
/// the answer is written in the option's own help so the behavior is discoverable
/// rather than magic.
public enum BareOptionValue {
    /// Option spelling → the value to supply when it is written bare.
    static let defaults: [String: String] = [
        "--props": Tree.defaultPropertyPaths.joined(separator: ","),
    ]

    /// The argument vector with every bare option in ``defaults`` given its value.
    ///
    /// An option is bare when nothing follows it, or when what follows is another
    /// option. Everything after a `--` terminator is left alone: those are operands, and
    /// a value that happens to read like an option spelling is still an operand.
    ///
    /// - Parameter arguments: The command line, without the program name.
    /// - Returns: The same arguments, with a value inserted after each bare option.
    public static func filled(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var terminated = false
        for (index, argument) in arguments.enumerated() {
            result.append(argument)
            if argument == "--" { terminated = true }
            guard !terminated, let value = defaults[argument] else { continue }
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            if next == nil || next?.hasPrefix("-") == true {
                result.append(value)
            }
        }
        return result
    }
}
