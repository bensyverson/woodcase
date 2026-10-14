//
//  SchemaPostItReport.swift
//  Woodcase
//

import Foundation

/// The post-it metadata convention, flattened for a machine reader.
///
/// What `woodcase schema postit --json` prints. Every row comes from ``PenPostIt/keys``,
/// the same vocabulary a refused write lists back, so the table cannot drift from the
/// check. See <doc:PenPostItConvention>.
public struct SchemaPostItReport: Friendly {
    /// Builds the report.
    public init() {
        type = PenPostIt.typeValue
        summary = Self.summaryText
        keys = PenPostIt.keys.map(Key.init)
    }

    /// The name the convention goes by in `woodcase schema`: `postit`.
    public let type: String

    /// One sentence saying what the convention is.
    public let summary: String

    /// Every key of a post-it's metadata, in reading order.
    public let keys: [Key]

    /// The summary every rendering of the table opens with.
    public static let summaryText =
        "keys of a note's metadata.woodcase (every note is a post-it); a write is held to them, a file is not"

    // MARK: - Key

    /// One key of the convention.
    public struct Key: Friendly {
        /// Describes one key.
        ///
        /// - Parameter key: The convention key.
        public init(_ key: PenMetadata.WoodcaseKey) {
            self.key = key.path
            spellings = key.spellings
            takes = switch key.shape {
            case .number: key.constraint.flatMap { $0.limitsValues ? $0.summary : nil } ?? "any number"
            case .any: "any JSON"
            case .textSpans: "an object"
            case .string, .oneOf, .hexColor, .utcTimestamp: "any string"
            }
            summary = key.summary
        }

        /// The path `set` writes it at, such as `common.metadata.woodcase.state`.
        public let key: String

        /// The values it takes; empty for any value of the kind ``takes`` names.
        public let spellings: [String]

        /// What it takes when ``spellings`` is empty: `any string`, `any number`, `any
        /// JSON`, or the range a number must keep to (`> 0, in points` for `fontSize`).
        public let takes: String

        /// One sentence saying what it holds.
        public let summary: String
    }
}
