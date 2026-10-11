//
//  PenTextSpans+Metadata.swift
//  Woodcase
//

import Foundation

/// Spans as a node's `metadata.woodcase.spans` stores them.
///
/// ```json
/// "metadata": { "type": "woodcase", "woodcase": { "spans": {
///   "text": "Make this bold",
///   "runs": [ { "start": 10, "end": 14, "fontWeight": "700", "fill": "#E5484D" } ]
/// } } }
/// ```
///
/// `text` is the content the runs were made for. Each run has `start` and `end`, UTF-16
/// offsets into it with `0 ≤ start ≤ end ≤` its length, and any of the style keys
/// ``PenTextRun/WireKey`` lists, spelled as the format spells a text node's own:
/// `fontWeight` a string (`"700"`, or a keyword such as `"bold"` on reading),
/// `fontStyle` `"italic"` or `"normal"`, `fill` a hex color, `fontSize` a positive number,
/// `underline` and `strikethrough` booleans. Any other key is refused, so a misspelled
/// style key is caught where it is written rather than silently drawn plain.
public extension PenTextSpans {
    /// Why a metadata value is not spans Woodcase can draw.
    struct WireError: Error, Friendly, CustomStringConvertible {
        /// What is wrong, as one clause: `run 2 has an unknown key "bold"`.
        public var reason: String

        /// Creates an error.
        ///
        /// - Parameter reason: What is wrong.
        public init(reason: String) {
            self.reason = reason
        }

        /// The reason.
        public var description: String {
            reason
        }
    }

    /// The shape spans are written in, for a message: `{text, runs: [{start, end, …}]}`.
    static let wireForm = "{text, runs: [{start, end, fontFamily?, fontSize?, fontWeight?, fontStyle?, fill?, "
        + "underline?, strikethrough?}]}"

    /// Reads spans from their stored form.
    ///
    /// - Parameter value: The value of `metadata.woodcase.spans`.
    /// - Throws: ``WireError`` naming the first thing that is not the stored form.
    init(metadataValue value: AnyCodable) throws(WireError) {
        guard case let .dictionary(object) = value else {
            throw WireError(reason: "spans are an object, \(Self.wireForm)")
        }
        if let extra = object.keys.sorted().first(where: { $0 != "text" && $0 != "runs" }) {
            throw WireError(reason: "spans have an unknown key \"\(extra)\"; they hold only text and runs")
        }
        guard case let .string(text)? = object["text"] else {
            throw WireError(reason: "spans need text: the content the runs were made for")
        }
        guard case let .array(items)? = object["runs"] else {
            throw WireError(reason: "spans need runs: an array of {start, end, …}")
        }
        let length = text.utf16.count
        var runs: [PenTextRun] = []
        for (index, item) in items.enumerated() {
            try runs.append(PenTextRun(metadataValue: item, number: index + 1, textLength: length))
        }
        self.init(text: text, runs: runs)
    }

    /// The spans in their stored form.
    var metadataValue: AnyCodable {
        .dictionary(["text": .string(text), "runs": .array(runs.map(\.metadataValue))])
    }
}
