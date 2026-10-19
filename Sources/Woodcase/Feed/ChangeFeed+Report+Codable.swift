//
//  ChangeFeed+Report+Codable.swift
//  Woodcase
//

import Foundation

public extension ChangeFeed.Report {
    /// The report's keys on the wire.
    private enum CodingKeys: String, CodingKey {
        case file, identity, revision, since, cursor, origin, restarted, unlogged, changes
    }

    /// Reads a report, its cursors from their tokens.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when a key is missing or a cursor is not a token.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            file: container.decode(String.self, forKey: .file),
            identity: container.decode(String.self, forKey: .identity),
            revision: container.decode(String.self, forKey: .revision),
            since: Self.cursor(.since, in: container),
            cursor: Self.cursor(.cursor, in: container),
            origin: container.decode(Origin.self, forKey: .origin),
            restarted: container.decode(Bool.self, forKey: .restarted),
            unlogged: container.decodeIfPresent(Unlogged.self, forKey: .unlogged),
            changes: container.decode([ActivityChangeSummary].self, forKey: .changes)
        )
    }

    /// Writes a report, its cursors as tokens and an explained file's `unlogged` as `null`.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(identity, forKey: .identity)
        try container.encode(revision, forKey: .revision)
        try container.encode(since.token, forKey: .since)
        try container.encode(cursor.token, forKey: .cursor)
        try container.encode(origin, forKey: .origin)
        try container.encode(restarted, forKey: .restarted)
        try container.encode(unlogged, forKey: .unlogged)
        try container.encode(changes, forKey: .changes)
    }

    /// A cursor read back from its token.
    private static func cursor(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ActivityCursor {
        let token = try container.decode(String.self, forKey: key)
        guard let cursor = ActivityCursor(token: token) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "\"\(token)\" is not a cursor token"
            )
        }
        return cursor
    }
}
