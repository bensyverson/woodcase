//
//  PropertyAssignment.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// One `key=value` a mutating verb was given, with the value already typed.
///
/// A command line carries only strings, and a .pen file carries numbers, booleans,
/// colors, variable references and whole objects. Somewhere the one has to become
/// the other, and guessing wrongly writes a *plausible wrong value* into a design —
/// `"240"` where `240` belongs. So the rules are few, total, and printed in every
/// verb's help as ``valueRules``:
///
/// | Written | Becomes |
/// |---|---|
/// | `240`, `-12`, `0.5`, `1e3` | a number |
/// | `true`, `false` | a boolean |
/// | `null` | null — which *clears* the property it is written to |
/// | `[…]`, `{…}` | JSON, parsed as written |
/// | `"…"` | the string inside the quotes, whatever it looks like |
/// | anything else | a string — `#ff8800`, `$brand`, `fill_container`, `Hello there` |
///
/// The last row is the important one: a color, a variable reference and a sizing
/// keyword are all *strings* in a .pen file, so they need no syntax of their own. The
/// quoting row is the escape hatch for the rare case where a string looks like
/// something else — a node named `42`, or the text `true`.
///
/// Only the first `=` splits, so a value may contain as many more as it likes.
///
/// `null` is the row that repays reading twice. On a node it clears the property. In an
/// *override* it is stored, and clears the property wherever that instance draws — the
/// override itself stays, and reads back. Removing an override is `override --unset`,
/// which is a different thing with a different result.
struct PropertyAssignment: Friendly {
    /// Creates an assignment.
    ///
    /// - Parameters:
    ///   - key: The property path, or the raw .pen name for an override.
    ///   - value: The typed value.
    init(key: String, value: AnyCodable) {
        self.key = key
        self.value = value
    }

    /// The property path (`kind.width`) — or, for `override`, the raw .pen name
    /// (`content`) and optionally a name path into a copy (`Title/kind.content`).
    let key: String

    /// The value, in the .pen file's own JSON shape.
    let value: AnyCodable

    /// The value rules, as a verb's help prints them.
    ///
    /// The JSON example is the fill literal ``Woodcase/NodePropertyCodec`` itself
    /// hands to a caller who gets a fill wrong, so the help and the refusal cannot
    /// teach two different shapes — this text used to offer `{"type":"solid"}`,
    /// which no .pen decoder has ever accepted.
    static var valueRules: String {
        """
        Values are typed by how they are written: 240 and 0.5 are numbers, true and \
        false are booleans, null clears the property it is written to (in an override \
        it is stored, and `override --unset` is what removes one), [8,16] and \
        \(fillExample) are JSON, and "42" is the string 42. Anything else is a string \
        — which is what a #ff8800 color, a $variable reference and the \
        fill_container / fit_content keywords already are.
        """
    }

    /// A fill literal the codec accepts, for the help text's JSON example.
    private static var fillExample: String {
        NodePropertyCodec.shape(of: "fills")?.example ?? "[8,16]"
    }

    // MARK: - Parsing

    /// Parses one `key=value`.
    ///
    /// - Parameter raw: The argument as typed.
    /// - Returns: The key and its typed value.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when there is no `=`, when
    ///   the key is empty, or when a `[`/`{`/`"` value is not valid JSON.
    static func parse(_ raw: String) throws -> PropertyAssignment {
        guard let separator = raw.firstIndex(of: "=") else {
            throw CommandFailure(
                message: "\(raw) is not an assignment — write it as key=value, for example "
                    + "kind.content=Hello. \(valueRules)",
                exitCode: .usage
            )
        }
        let key = String(raw[raw.startIndex ..< separator])
        guard !key.isEmpty else {
            throw CommandFailure(
                message: "\(raw) has no key before its = — write it as key=value.",
                exitCode: .usage
            )
        }
        return try PropertyAssignment(
            key: key,
            value: value(of: String(raw[raw.index(after: separator)...]), for: key)
        )
    }

    /// Every property a verb was given, from the command line and from `-F` together.
    ///
    /// A `key=value` on the command line wins over the same key in the file: the more
    /// specific of the two is the one the caller typed just now.
    ///
    /// - Parameters:
    ///   - assignments: The `key=value` arguments, in the order they were written.
    ///   - file: A JSON object of properties to start from, or `nil`.
    /// - Returns: The merged properties.
    /// - Throws: ``CommandFailure`` when an assignment will not parse, when the same
    ///   key is assigned twice on the command line, or when `file` is not a readable
    ///   JSON object.
    static func properties(from assignments: [String], file: String?) throws -> [String: AnyCodable] {
        var properties = try file.map { try object(fromFileAt: $0) } ?? [:]
        var seen: Set<String> = []
        for raw in assignments {
            let assignment = try parse(raw)
            guard seen.insert(assignment.key).inserted else {
                throw CommandFailure(
                    message: "\(assignment.key) is assigned twice. Give each key once, so it is "
                        + "clear which value is meant.",
                    exitCode: .usage
                )
            }
            properties[assignment.key] = assignment.value
        }
        return properties
    }

    // MARK: - Private

    /// The typed value behind the `=`.
    private static func value(of raw: String, for key: String) throws -> AnyCodable {
        switch raw {
        case "": return .string("")
        case "null": return .null
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if let first = raw.first, first == "[" || first == "{" || first == "\"" {
            return try json(raw, for: key)
        }
        if let first = raw.first, first.isNumber || first == "-" || first == "+" || first == "." {
            if let integer = Int(raw) { return .int(integer) }
            if let number = Double(raw), number.isFinite { return .double(number) }
        }
        return .string(raw)
    }

    /// A `[`, `{` or `"` value, parsed as the JSON it announced itself to be.
    private static func json(_ raw: String, for key: String) throws -> AnyCodable {
        do {
            return try JSONDecoder().decode(AnyCodable.self, from: Data(raw.utf8))
        } catch {
            throw CommandFailure(
                message: "The value of \(key) starts with \(raw.prefix(1)), so it is read as JSON, "
                    + "but it is not valid JSON. Quote the whole argument if the shell is "
                    + "splitting it, or write a plain string without the leading character.",
                exitCode: .usage
            )
        }
    }

    /// The JSON object a `-F` file holds.
    private static func object(fromFileAt path: String) throws -> [String: AnyCodable] {
        let data = try InputFile.data(at: path)
        let value: AnyCodable
        do {
            value = try JSONDecoder().decode(AnyCodable.self, from: data)
        } catch {
            throw CommandFailure(
                message: "\(path) is not JSON: \(error.localizedDescription)",
                exitCode: .usage
            )
        }
        guard case let .dictionary(properties) = value else {
            throw CommandFailure(
                message: "\(path) must hold a JSON object of property names to values, "
                    + #"like {"kind.width": 240}."#,
                exitCode: .usage
            )
        }
        return properties
    }
}
