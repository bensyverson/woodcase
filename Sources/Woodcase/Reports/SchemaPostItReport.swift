//
//  SchemaPostItReport.swift
//  Woodcase
//

import Foundation

/// The post-it metadata convention, flattened for a machine reader.
///
/// What `woodcase schema postit --json` prints. Every row comes from ``PenPostIt/Key``,
/// the same vocabulary a refused write lists back, so the table cannot drift from the
/// check. See <doc:PenPostItConvention>.
public struct SchemaPostItReport: Friendly {
    /// Builds the report.
    public init() {
        type = PenPostIt.typeValue
        summary = Self.summaryText
        keys = PenPostIt.Key.allCases.map(Key.init)
    }

    /// The `metadata.type` that marks a node as a post-it.
    public let type: String

    /// One sentence saying what the convention is.
    public let summary: String

    /// Every key of a post-it's metadata, in reading order.
    public let keys: [Key]

    /// The summary every rendering of the table opens with.
    public static let summaryText =
        "keys of a note's metadata when metadata.type is \"\(PenPostIt.typeValue)\"; a write is held to them, a file is not"

    // MARK: - Key

    /// One key of the convention.
    public struct Key: Friendly {
        /// Describes one key.
        ///
        /// - Parameter key: The convention key.
        public init(_ key: PenPostIt.Key) {
            self.key = "common.metadata.\(key.rawValue)"
            spellings = key.spellings
            summary = key.summary
        }

        /// The path `set` writes it at, such as `common.metadata.kind`.
        public let key: String

        /// The values it takes; empty for any string.
        public let spellings: [String]

        /// One sentence saying what it holds.
        public let summary: String
    }
}
