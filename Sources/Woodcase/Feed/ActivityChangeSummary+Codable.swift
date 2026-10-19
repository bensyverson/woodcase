//
//  ActivityChangeSummary+Codable.swift
//  Woodcase
//

import Foundation

/// ``ActivityChangeSummary`` writes its ``ActivityChangeSummary/time`` the way the log
/// writes an ``ActivityEvent``'s — ISO-8601, UTC, milliseconds — so a feed's JSON and the
/// log's lines carry one timestamp format, whatever encoder the caller holds.
public extension ActivityChangeSummary {
    /// The summary's keys on the wire.
    private enum CodingKeys: String, CodingKey {
        case time, identity, file, op, revision, batch, changes
    }

    /// Reads a summary.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when a key is missing or ``time`` is not an ISO-8601
    ///   timestamp with fractional seconds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stamp = try container.decode(String.self, forKey: .time)
        do {
            time = try ActivityEvent.roundedToMilliseconds(Date(stamp, strategy: ActivityEvent.timeFormat))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .time, in: container,
                debugDescription: "'\(stamp)' is not an ISO-8601 UTC timestamp with fractional seconds"
            )
        }
        identity = try container.decode(String.self, forKey: .identity)
        file = try container.decode(String.self, forKey: .file)
        op = try container.decode(ActivityEvent.Kind.self, forKey: .op)
        revision = try container.decode(String.self, forKey: .revision)
        batch = try container.decodeIfPresent(String.self, forKey: .batch)
        changes = try container.decode([Change].self, forKey: .changes)
    }

    /// Writes a summary.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ActivityEvent.wireTime(time), forKey: .time)
        try container.encode(identity, forKey: .identity)
        try container.encode(file, forKey: .file)
        try container.encode(op, forKey: .op)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(batch, forKey: .batch)
        try container.encode(changes, forKey: .changes)
    }
}
