//
//  BatchErrorMessage+Override.swift
//  Woodcase
//

import Foundation

/// The override a refused `set` should have been, spelled out ready to run.
extension BatchErrorMessage {
    /// The placeholder written when the refused verb carried no properties.
    static let placeholderAssignment = "name=value"

    /// Each property as the `key=value` argument `woodcase override` takes, sorted by key:
    /// a string as itself, anything else as compact JSON.
    ///
    /// - Parameter properties: The override payload, keyed by raw .pen key.
    /// - Returns: The assignments, or the placeholder alone when there are none.
    nonisolated static func overrideAssignments(_ properties: [String: AnyCodable]) -> [String] {
        guard !properties.isEmpty else { return [placeholderAssignment] }
        return properties.keys.sorted().map { key in
            let value: String = if case let .string(text)? = properties[key] {
                text
            } else {
                compactJSON(properties[key] ?? .null)
            }
            return "\(key)=\(value)"
        }
    }

    /// The assignments as shell arguments, each quoted so a `$` or a space survives.
    nonisolated static func overrideArguments(_ properties: [String: AnyCodable]) -> String {
        guard !properties.isEmpty else { return placeholderAssignment }
        return overrideAssignments(properties).map(shellQuoted).joined(separator: " ")
    }

    /// The batch line that writes the override.
    nonisolated static func overrideLine(_ address: String, _ properties: [String: AnyCodable]) -> String {
        let props = properties.isEmpty ? "{…}" : compactJSON(.dictionary(properties))
        return #"{"op":"override","target":\#(compactJSON(.string(address))),"props":\#(props)}"#
    }

    /// A word quoted for a POSIX shell.
    nonisolated static func shellQuoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// A value as compact JSON, keys sorted and slashes left alone.
    private nonisolated static func compactJSON(_ value: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
