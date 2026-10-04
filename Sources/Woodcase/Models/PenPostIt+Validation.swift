//
//  PenPostIt+Validation.swift
//  Woodcase
//

import Foundation

/// Holding a write to a post-it's metadata to the convention.
///
/// Only what a write *changes* is checked: a key whose value equals what the node
/// already holds passes, so a file written before the convention — or by hand, with a
/// misspelling — still opens and can still be edited around the legacy value.
public extension PenPostIt {
    /// One key of a metadata write the convention does not accept.
    struct Violation: Friendly {
        /// Creates a violation.
        ///
        /// - Parameters:
        ///   - key: The key whose value is refused.
        ///   - value: The refused value.
        ///   - accepted: The spellings the key takes, or `["a string"]` for a free-text key.
        ///   - suggestion: The closest accepted spelling, when one is close.
        public init(key: Key, value: AnyCodable, accepted: [String], suggestion: String?) {
            self.key = key
            self.value = value
            self.accepted = accepted
            self.suggestion = suggestion
        }

        /// The key whose value is refused.
        public var key: Key
        /// The refused value.
        public var value: AnyCodable
        /// The spellings the key takes, or `["a string"]` for a free-text key.
        public var accepted: [String]
        /// The closest accepted spelling, when one is close.
        public var suggestion: String?
    }

    /// The first key of a metadata write the convention refuses, in ``Key`` order.
    ///
    /// - Parameters:
    ///   - metadata: The whole metadata object as it will be written.
    ///   - current: The metadata the node holds now, if any; a key left at its current
    ///     value is not checked.
    /// - Returns: The refusal, or `nil` when the write is a post-it's and every key it
    ///   changes is well formed, or when it is not a post-it's at all.
    static func violation(
        in metadata: [String: AnyCodable],
        comparedTo current: PenMetadata?
    ) -> Violation? {
        guard metadata[Key.type.rawValue] == .string(typeValue) else { return nil }
        for key in Key.allCases where key != .type {
            guard let value = metadata[key.rawValue], value != .null, value != current?[key.rawValue]
            else { continue }
            if let violation = violation(of: key, value) { return violation }
        }
        return nil
    }

    /// The JSON a value is written as, for a message or an unrecognized field.
    internal static func json(_ value: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Private

    /// What a free-text key's refusal says it takes.
    private static let anyString = "a string"

    /// Whether one key's value is refused.
    private static func violation(of key: Key, _ value: AnyCodable) -> Violation? {
        guard case let .string(text) = value else {
            let accepted = key.spellings.isEmpty ? [anyString] : key.spellings
            return Violation(key: key, value: value, accepted: accepted, suggestion: nil)
        }
        switch key {
        case .kind, .state:
            guard !key.spellings.contains(text) else { return nil }
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: closest(to: text, in: key.spellings))
        case .tint:
            guard tint(text) == nil else { return nil }
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil)
        case .type, .author, .leaf, .stage, .copiedFrom:
            return nil
        }
    }

    /// The spelling a misspelling most likely meant, or `nil` when none is close.
    ///
    /// Case is ignored, and a spelling counts as close within two edits, or a third of
    /// its length for a longer one, so `questoin` finds `question` while `zebra` finds
    /// nothing.
    private static func closest(to text: String, in spellings: [String]) -> String? {
        let needle = text.lowercased()
        // `min(by:)` keeps the first of equals, so a tie goes to the earlier spelling.
        return spellings
            .map { (spelling: $0, distance: IconNameMatcher.levenshteinDistance(needle, $0)) }
            .filter { $0.distance <= max(2, $0.spelling.count / 3) }
            .min { $0.distance < $1.distance }?
            .spelling
    }
}
