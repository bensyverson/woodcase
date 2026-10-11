//
//  PenRichTextMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Flattens a legacy rich text node's styled runs into one plain string.
///
/// Up to 2.10 a text node's `content` could be an array of styled runs, each with its
/// own font, weight, color and decorations. 2.17 dropped the array: `content` is a
/// string or a `$variable` and nothing else.
///
/// ```json
/// "content": [
///   { "content": "Bold ",   "fontWeight": "700" },
///   { "content": "Italic ", "fontStyle": "italic" },
///   { "content": "Colored", "fill": "#FF0000" }
/// ]
/// ```
///
/// becomes `"content": "Bold Italic Colored"` — the runs concatenated in order with no
/// separator. Version 1.2.7 of the format's own editor drops the property outright and
/// loses the words with it; keeping the text is a deliberate departure.
///
/// ## Where the styling goes
///
/// On a `text` node the runs' styling is kept: each styled run becomes a ``PenTextRun``
/// over its stretch of the joined string, in UTF-16 offsets, written to the node's
/// `metadata.woodcase.spans` (<doc:PenRichText>) with the joined string as the text the
/// runs were made for. A run's `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`
/// (`italic` or `normal`), `fill` (a hex color), `underline` and `strikethrough` carry
/// over when written as literal values. What spans cannot hold — `letterSpacing`,
/// `lineHeight`, alignment, `href`, a `$variable`, a fill that is not one hex color — is
/// dropped, and one warning names it. A text whose runs carry no styling gets no spans.
///
/// On a `note`, `prompt` or `context`, and on a `ref`'s descendant override (which names
/// no type), the per-run styling is discarded and reported through the diagnostic
/// collector: a note's rich text is markdown in its `content`, not spans.
///
public struct PenRichTextMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// The 2.11 shape: only a legacy (2.8 – 2.10) document gets this rule.
    public let target = PenFormatVersion.oldestModern

    /// Replaces an array-valued `content` with the concatenation of its runs' text.
    ///
    /// Nodes whose `content` is already a string, or absent, are left untouched and emit
    /// no diagnostic.
    public func apply(
        toNode node: inout [String: AnyCodable],
        id: String?,
        diagnostics: PenDiagnosticCollector?
    ) {
        guard case let .array(runs)? = node["content"] else { return }

        let joined = runs.compactMap(text(ofRun:)).joined()
        node["content"] = .string(joined)
        guard node["type"] == .string("text") else {
            diagnostics?.warn(
                "Rich text was flattened to a plain string; per-run styling was discarded.",
                stage: .migration,
                nodeID: id
            )
            return
        }
        let (styled, dropped) = spans(of: runs)
        if !styled.isEmpty {
            var metadata = PenMetadata(object: object(node["metadata"]))
            metadata.textSpans = PenTextSpans(text: joined, runs: styled)
            node["metadata"] = .dictionary(metadata.object)
        }
        if !dropped.isEmpty {
            diagnostics?.warn(
                "Rich text was flattened to a plain string and its styling kept as spans, but spans cannot "
                    + "hold \(dropped.sorted().joined(separator: ", ")); that styling was discarded.",
                stage: .migration,
                nodeID: id
            )
        }
    }

    /// The text of one run, or nil when the run carries none.
    private func text(ofRun run: AnyCodable) -> String? {
        guard case let .dictionary(fields) = run,
              case let .string(text)? = fields["content"]
        else { return nil }
        return text
    }

    /// The styled runs over the joined string, and the style keys that could not be kept.
    private func spans(of runs: [AnyCodable]) -> (runs: [PenTextRun], dropped: Set<String>) {
        var styled: [PenTextRun] = []
        var dropped: Set<String> = []
        var offset = 0
        for run in runs {
            guard let text = text(ofRun: run), case let .dictionary(fields) = run else { continue }
            let length = text.utf16.count
            defer { offset += length }
            var converted = PenTextRun(start: offset, end: offset + length)
            var carriesStyle = false
            for (key, value) in fields where key != "content" {
                if carry(key, value, onto: &converted) {
                    carriesStyle = true
                } else {
                    dropped.insert(key)
                }
            }
            if carriesStyle, length > 0 { styled.append(converted) }
        }
        return (styled, dropped)
    }

    /// Copies one 2.10 style key onto a run, when spans can hold its value.
    ///
    /// - Returns: Whether the key was carried.
    private func carry(_ key: String, _ value: AnyCodable, onto run: inout PenTextRun) -> Bool {
        if case let .string(text) = value, text.hasPrefix("$") { return false }
        switch (key, value) {
        case let ("fontFamily", .string(family)) where !family.isEmpty:
            run.fontFamily = family
        case let ("fontSize", .int(size)) where size > 0:
            run.fontSize = Double(size)
        case let ("fontSize", .double(size)) where size > 0:
            run.fontSize = size
        case ("fontWeight", _):
            guard let weight = PenTextRun.weight(value) else { return false }
            run.fontWeight = weight
        case let ("fontStyle", .string(style)) where ["italic", "normal"].contains(style.lowercased()):
            run.isItalic = style.lowercased() == "italic"
        case let ("fill", .string(hex)):
            guard let color = PenHexColor(hex) else { return false }
            run.fill = color
        case let ("underline", .bool(flag)):
            run.underline = flag
        case let ("strikethrough", .bool(flag)):
            run.strikethrough = flag
        default:
            return false
        }
        return true
    }

    /// A metadata value as an object, or an empty one.
    private func object(_ value: AnyCodable?) -> [String: AnyCodable] {
        guard case let .dictionary(object)? = value else { return [:] }
        return object
    }
}
