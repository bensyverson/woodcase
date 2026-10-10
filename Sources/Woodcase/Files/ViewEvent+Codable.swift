//
//  ViewEvent+Codable.swift
//  Woodcase
//

import Foundation

/// The `views.jsonl` wire format, with the same time format and encoder settings as
/// the activity log's (``ActivityEvent/wireTime(_:)``, ``ActivityEvent/makeEncoder()``).
public extension ViewEvent {
    /// The field names of the wire format. Changing one is a format change.
    internal enum CodingKeys: String, CodingKey {
        case time, identity, file, verb, revision, nodes, scope, covered
    }

    /// Decodes a view from one line's JSON.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if a field is missing, the verb or scope is unknown, or
    ///   the time is not an ISO-8601 timestamp.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stamp = try container.decode(String.self, forKey: .time)
        do {
            time = try ActivityEvent.roundedToMilliseconds(Date(stamp, strategy: ActivityEvent.timeFormat))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .time,
                in: container,
                debugDescription: "'\(stamp)' is not an ISO-8601 UTC timestamp with fractional seconds"
            )
        }
        identity = try container.decode(String.self, forKey: .identity)
        file = try container.decode(String.self, forKey: .file)
        verb = try container.decode(Verb.self, forKey: .verb)
        revision = try container.decode(String.self, forKey: .revision)
        nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .nodes
        covered = try container.decodeIfPresent(Int.self, forKey: .covered) ?? nodes.count
    }

    /// Encodes the view as one line's JSON.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Anything the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ActivityEvent.wireTime(time), forKey: .time)
        try container.encode(identity, forKey: .identity)
        try container.encode(file, forKey: .file)
        try container.encode(verb, forKey: .verb)
        try container.encode(revision, forKey: .revision)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(scope, forKey: .scope)
        try container.encode(covered, forKey: .covered)
    }

    /// The view as one line of JSON, without the trailing newline.
    ///
    /// - Returns: The line's bytes.
    /// - Throws: Anything the encoder throws.
    func jsonLine() throws -> Data {
        try ActivityEvent.makeEncoder().encode(self)
    }

    /// Reads a view back from one line of JSON.
    ///
    /// - Parameters:
    ///   - line: The line's bytes, with or without a trailing newline.
    ///   - decoder: A decoder to reuse across lines.
    /// - Throws: `DecodingError` if the line is not a view.
    init(line: Data, using decoder: JSONDecoder) throws {
        self = try decoder.decode(ViewEvent.self, from: line)
    }
}

extension ViewEvent: JSONLinesRow {}
