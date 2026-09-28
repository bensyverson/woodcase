//
//  ActivityEvent+Codable.swift
//  Woodcase
//

import Foundation

/// The JSONL wire format, pinned here rather than left to an encoder's settings.
///
/// ``ActivityEvent`` writes and reads its own ``ActivityEvent/time`` as an ISO-8601
/// string, so a line is the same bytes whichever `JSONEncoder` produced it — a plain
/// `JSONEncoder()` cannot silently turn the timestamp into a floating-point number.
/// The only encoder settings that matter to the format are sorted keys and unescaped
/// slashes, which ``ActivityEvent/makeEncoder()`` applies.
public extension ActivityEvent {
    /// The timestamp format on the wire: ISO-8601, UTC, with milliseconds
    /// (`2026-08-29T16:31:04.123Z`). This is the format ``time`` is *parsed* with.
    static let timeFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// A timestamp in the wire format.
    ///
    /// The milliseconds are assembled here rather than left to ``timeFormat``, which
    /// *truncates* the fraction: `Date` holds a binary double, so a time built from
    /// `.123` is a hair under it and formats as `.122`. Rounding to whole milliseconds
    /// and printing that integer is what makes a line round-trip to an equal event.
    ///
    /// - Parameter date: The time to write.
    /// - Returns: Its ISO-8601 UTC form with three fractional digits.
    static func wireTime(_ date: Date) -> String {
        let total = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (total / 1000).rounded(.down)
        let milliseconds = Int(total - seconds * 1000)
        let whole = Date(timeIntervalSince1970: seconds).formatted(wholeSecondFormat)
        return "\(whole.dropLast()).\(String(format: "%03d", milliseconds))Z"
    }

    /// The same format without fractional seconds, ending in `Z`.
    internal static let wholeSecondFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// The field names of the wire format. Changing one is a format change.
    internal enum CodingKeys: String, CodingKey {
        case time, identity, file, op, nodes, paths, inverse, revision, batch
    }

    /// Decodes an event from one line's JSON.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if a required field is missing, or if ``time`` is not
    ///   an ISO-8601 timestamp.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stamp = try container.decode(String.self, forKey: .time)
        do {
            time = try Self.roundedToMilliseconds(Date(stamp, strategy: Self.timeFormat))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .time,
                in: container,
                debugDescription: "'\(stamp)' is not an ISO-8601 UTC timestamp with fractional seconds"
            )
        }
        identity = try container.decode(String.self, forKey: .identity)
        file = try container.decode(String.self, forKey: .file)
        op = try container.decode(Kind.self, forKey: .op)
        nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
        paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        inverse = try container.decodeIfPresent([EditOperation].self, forKey: .inverse) ?? []
        revision = try container.decode(String.self, forKey: .revision)
        batch = try container.decodeIfPresent(String.self, forKey: .batch)
    }

    /// Encodes the event as one line's JSON.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Anything the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.wireTime(time), forKey: .time)
        try container.encode(identity, forKey: .identity)
        try container.encode(file, forKey: .file)
        try container.encode(op, forKey: .op)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(paths, forKey: .paths)
        try container.encode(inverse, forKey: .inverse)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(batch, forKey: .batch)
    }

    // MARK: - Lines

    /// An encoder configured for the log's lines: keys in a stable order, and no
    /// `\/` escapes so that file paths and name paths stay readable.
    ///
    /// - Returns: A fresh encoder. `JSONEncoder` is not `Sendable`, so callers that
    ///   encode many events make one and reuse it rather than sharing a global.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The event as one line of JSON, without the trailing newline.
    ///
    /// - Parameter encoder: An encoder from ``makeEncoder()``.
    /// - Returns: The line's bytes.
    /// - Throws: Anything the encoder throws.
    func jsonLine(using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(self)
    }

    /// The event as one line of JSON, without the trailing newline.
    ///
    /// - Returns: The line's bytes.
    /// - Throws: Anything the encoder throws.
    func jsonLine() throws -> Data {
        try jsonLine(using: Self.makeEncoder())
    }

    /// Reads an event back from one line of JSON.
    ///
    /// - Parameters:
    ///   - line: The line's bytes, with or without a trailing newline.
    ///   - decoder: A decoder to reuse across lines.
    /// - Throws: `DecodingError` if the line is not an event.
    init(line: Data, using decoder: JSONDecoder) throws {
        self = try decoder.decode(ActivityEvent.self, from: line)
    }

    /// Reads an event back from one line of JSON.
    ///
    /// - Parameter line: The line's bytes, with or without a trailing newline.
    /// - Throws: `DecodingError` if the line is not an event.
    init(line: Data) throws {
        try self.init(line: line, using: JSONDecoder())
    }
}
