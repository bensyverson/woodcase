//
//  SSEEvent.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One Server-Sent Event, and the bytes it goes out as.
///
/// The wire format is three lines and a blank one:
///
/// ```text
/// id: 12
/// event: change
/// data: {"artboards":["Cnv01"],"file":"a1b2c3d4e5f6", …}
///
/// ```
///
/// `data` is always one JSON object. A payload that spans several lines is written as
/// several `data:` lines, which the browser rejoins with newlines — that is the format's
/// own rule, and getting it wrong silently truncates the JSON at the first newline.
public struct SSEEvent: Friendly {
    /// Creates an event with a rendered payload.
    ///
    /// - Parameters:
    ///   - id: The stream position, so a client that reconnects can say where it was.
    ///   - name: Which stream this belongs to.
    ///   - data: The payload's JSON.
    public init(id: Int, name: Name, data: String) {
        self.id = id
        self.name = name
        self.data = data
    }

    /// Creates an event by encoding a payload.
    ///
    /// - Parameters:
    ///   - id: The stream position.
    ///   - name: Which stream this belongs to.
    ///   - payload: The value to encode as the event's `data`.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    public init(id: Int, name: Name, payload: some Encodable) throws {
        try self.init(id: id, name: name, data: ViewerJSON.text(payload))
    }

    /// The streams the viewer publishes.
    ///
    /// Two, and the page needs no others: everything else it shows is a fragment it
    /// fetches after a `change`.
    public enum Name: String, Friendly, CaseIterable {
        /// A watched file changed on disk. Payload: ``ViewerChange``.
        case change
        /// The set of identities in the log, and how long ago each was seen.
        /// Payload: ``ViewerPresence``.
        case presence
    }

    /// The stream position.
    public let id: Int

    /// Which stream this belongs to.
    public let name: Name

    /// The payload's JSON.
    public let data: String

    /// The event as it goes out on the wire, blank line included.
    public var wireFormat: String {
        let lines = data.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "data: \($0)" }
            .joined(separator: "\n")
        return "id: \(id)\nevent: \(name.rawValue)\n\(lines)\n\n"
    }

    /// The comment a server sends to keep an idle stream — and any proxy in front of
    /// it — from timing out. A client parses nothing from it.
    public static let heartbeat = ": heartbeat\n\n"
}
