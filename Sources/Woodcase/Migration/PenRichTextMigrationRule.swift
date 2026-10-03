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
/// separator. Version 1.2.7 of the format's own editor drops the property outright and loses the words with it;
/// keeping the text is a deliberate departure, and the per-run styling is reported as
/// discarded through the diagnostic collector.
///
/// The rule keys on the *shape* of `content` rather than on the node's `type`, because a
/// `ref` node's `descendants` overrides carry properties with no `type` alongside them.
/// In the 2.8 – 2.10 schema `content` is only ever text content — on `text`, `note`,
/// `prompt` and `context` — so an array there is unambiguously a run list.
///
/// ## Variable references
///
/// A run's text is copied verbatim, so a lone `{"content": "$headline"}` run flattens to
/// `"$headline"` and still decodes as a variable reference. A `$name` run *among others*
/// concatenates into the surrounding text and reads as one long variable name; the format
/// has no escape for a literal `$`, so there is nothing better available here.
/// ``PenVariableResolver`` restores an undefined `$name` as literal text, which keeps the
/// rendered result right.
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

        node["content"] = .string(runs.compactMap(text(ofRun:)).joined())
        diagnostics?.warn(
            "Rich text was flattened to a plain string; per-run styling was discarded.",
            stage: .migration,
            nodeID: id
        )
    }

    /// The text of one run, or nil when the run carries none.
    private func text(ofRun run: AnyCodable) -> String? {
        guard case let .dictionary(fields) = run,
              case let .string(text)? = fields["content"]
        else { return nil }
        return text
    }
}
