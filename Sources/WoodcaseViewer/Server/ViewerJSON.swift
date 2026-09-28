//
//  ViewerJSON.swift
//  WoodcaseViewer
//

import Foundation

/// The one JSON encoding the viewer's endpoints and events use — and the decoder that
/// reads it back.
///
/// Sorted keys and unescaped slashes, so a response is byte-stable and a path in it is
/// readable; times in the activity log's own ISO-8601 form, to millisecond precision, so
/// a timestamp in an SSE event and the same timestamp in `activity.jsonl` are the same
/// string.
///
/// Both halves are public because the endpoints are an API: a consumer decoding
/// ``FileListReport`` or ``ViewerChange`` with a stock `JSONDecoder` would fail on every
/// date, and shipping a format without the decoder for it is shipping half a contract.
///
/// ```swift
/// let report = try ViewerJSON.decoder.decode(FileListReport.self, from: data)
/// ```
public enum ViewerJSON {
    /// The format times are written in — `ActivityEvent`'s, exactly.
    public static let timeFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// An encoder configured for responses.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(roundedToMilliseconds(date).formatted(timeFormat))
        }
        return encoder
    }

    /// Rounds a date to the millisecond the wire format carries.
    ///
    /// The same rounding `ActivityEvent` applies to its own times, applied here for the
    /// same reason and so that one instant recorded in both places is written as one
    /// string. The format carries whole milliseconds and nothing finer, so this is the
    /// precision a value survives a round trip at.
    ///
    /// - Parameter date: The time to round.
    /// - Returns: The same time, to the nearest whole millisecond.
    static func roundedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// A decoder that reads what ``encoder`` writes.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(text, strategy: timeFormat) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "'\(text)' is not an ISO-8601 time with milliseconds."
                ))
            }
            return date
        }
        return decoder
    }

    /// Encodes a value as JSON text.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: Its JSON.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    static func text(_ value: some Encodable) throws -> String {
        try String(decoding: encoder.encode(value), as: UTF8.self)
    }
}
