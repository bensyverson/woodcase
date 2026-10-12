//
//  PenPostIt+Validation.swift
//  Woodcase
//

import Foundation

/// Holding a write to a node's `metadata.woodcase` to the convention.
///
/// Only what a write *changes* is checked, each key read through
/// ``PenMetadata/subscript(woodcase:)``: a key whose value equals what the node already
/// holds — in either spelling — passes, so a file written before the convention, or by
/// hand with a misspelling, still opens and can still be edited around the legacy value.
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
        ///   - reason: What is wrong inside a structured value, such as spans.
        public init(
            key: PenMetadata.WoodcaseKey, value: AnyCodable, accepted: [String], suggestion: String?,
            reason: String? = nil
        ) {
            self.key = key
            self.value = value
            self.accepted = accepted
            self.suggestion = suggestion
            self.reason = reason
        }

        /// The key whose value is refused.
        public var key: PenMetadata.WoodcaseKey
        /// The refused value.
        public var value: AnyCodable
        /// The spellings the key takes, or `["a string"]` for a free-text key.
        public var accepted: [String]
        /// The closest accepted spelling, when one is close.
        public var suggestion: String?
        /// What is wrong inside a structured value (``PenMetadata/WoodcaseKey/Shape/textSpans``),
        /// or `nil` for a key whose value is a single spelling.
        public var reason: String?
    }

    /// The first key of a metadata write the convention refuses, in
    /// ``PenMetadata/WoodcaseKey`` order.
    ///
    /// - Parameters:
    ///   - metadata: The whole metadata object as it will be written.
    ///   - current: The metadata the node holds now, if any; a key left at its current
    ///     value is not checked.
    ///   - kind: The kind of the node written to, when known: a prompt's `state` is held
    ///     to ``RunState`` (``PenMetadata/WoodcaseKey/shape(on:)``). `nil` holds every key
    ///     to its ``PenMetadata/WoodcaseKey/shape``.
    /// - Returns: The refusal, or `nil` when every Woodcase key the write changes is
    ///   well formed.
    static func violation(
        in metadata: [String: AnyCodable],
        comparedTo current: PenMetadata?,
        on kind: PenNode.Kind? = nil
    ) -> Violation? {
        let written = PenMetadata(object: metadata)
        for key in PenMetadata.WoodcaseKey.allCases {
            guard let value = written[woodcase: key], value != .null, value != current?[woodcase: key]
            else { continue }
            let shape = kind.map { key.shape(on: $0) } ?? key.shape
            if let violation = violation(of: key, shape: shape, value) { return violation }
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

    /// What a numeric key's refusal says it takes.
    private static let anyNumber = "a number"

    /// Whether one key's value is refused.
    private static func violation(
        of key: PenMetadata.WoodcaseKey, shape: PenMetadata.WoodcaseKey.Shape, _ value: AnyCodable
    ) -> Violation? {
        switch (shape, value) {
        case (.any, _), (.string, .string), (.number, .int), (.number, .double):
            return nil
        case (.string, _):
            return Violation(key: key, value: value, accepted: [anyString], suggestion: nil)
        case (.number, _):
            return Violation(key: key, value: value, accepted: [anyNumber], suggestion: nil)
        case let (.oneOf(spellings), .string(text)):
            guard !spellings.contains(text) else { return nil }
            return Violation(key: key, value: value, accepted: spellings, suggestion: closest(to: text, in: spellings))
        case let (.hexColor, .string(text)):
            guard tint(text) == nil else { return nil }
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil)
        case let (.oneOf(spellings), _):
            return Violation(key: key, value: value, accepted: spellings, suggestion: nil)
        case (.hexColor, _):
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil)
        case let (.utcTimestamp, .string(text)):
            guard PenComment.date(createdAt: text) == nil else { return nil }
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil)
        case (.utcTimestamp, _):
            return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil)
        case (.textSpans, _):
            do {
                _ = try PenTextSpans(metadataValue: value)
                return nil
            } catch {
                return Violation(key: key, value: value, accepted: key.spellings, suggestion: nil, reason: error.reason)
            }
        }
    }

    /// The spelling a misspelling most likely meant, or `nil` when none is close.
    ///
    /// Case is ignored, and a spelling counts as close within two edits, or a third of
    /// its length for a longer one, so `reslved` finds `resolved` while `zebra` finds
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
