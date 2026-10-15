//
//  PenTextDecoration.swift
//  Woodcase
//

import Foundation

/// A text node's underline and strikethrough, kept where Pen cannot strip them.
///
/// Pen strips `underline` and `strikethrough` from a text node when it opens a file —
/// although both are in the schema it publishes — and keeps metadata
/// (`project/2026-09-26-what-pen-drops-from-a-file.md`). So a text that carries either
/// natively also holds them in its `metadata.woodcase.textDecoration`, with the content
/// they were made for:
///
/// ```json
/// "underline": true,
/// "metadata": { "type": "woodcase", "woodcase": { "textDecoration": {
///   "text": "Read the terms", "underline": true, "strikethrough": false
/// } } }
/// ```
///
/// Woodcase keeps the two in step on every read and write (``PenDocument/protectingTextDecoration()``):
/// a native key restores from the protection, and the protection is rewritten from the
/// native keys. When Pen edits the words, which it can do but cannot see this key, the
/// protection is stale (``isStale(for:)``) but still restores: both keys cover the whole
/// text, and a whole-text style follows the text into new words, as a whole-text run of a
/// text's spans does (<doc:PenRichText>, Ben's ruling of 2026-10-15). It is then made again
/// for the new words.
///
/// It is a key of its own, not a whole-text run in `metadata.woodcase.spans`: spans are the
/// author's styling, written whole by a rich-text editor, so a run Woodcase kept in step
/// with the native keys would be indistinguishable from one the author made — and removing
/// an underline natively would then have to guess whether a whole-text underlined run was
/// the author's. A key with one writer, the protection itself, has no such ambiguity.
public struct PenTextDecoration: Friendly {
    /// The content the protection was made for.
    public var text: String

    /// Whether the text is underlined.
    public var underline: Bool

    /// Whether the text is struck through.
    public var strikethrough: Bool

    /// Creates a protection.
    ///
    /// - Parameters:
    ///   - text: The content it is made for.
    ///   - underline: Whether the text is underlined.
    ///   - strikethrough: Whether the text is struck through.
    public init(text: String, underline: Bool, strikethrough: Bool) {
        self.text = text
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// Whether the protection was made for other content than `content`: the words were
    /// edited where the protection could not follow them. It still restores, and is made
    /// again for `content` on the next read or write. Compared as UTF-16 code units, as
    /// ``PenTextSpans/isStale(for:)`` compares.
    ///
    /// - Parameter content: The node's content as it is now.
    /// - Returns: `true` when `content` differs from ``text``.
    public func isStale(for content: String) -> Bool {
        !content.utf16.elementsEqual(text.utf16)
    }

    // MARK: - Wire form

    /// The shape the protection is written in, for a message.
    public static let wireForm = "{text, underline, strikethrough}"

    /// The keys it holds.
    private enum WireKey: String, CaseIterable {
        case text, underline, strikethrough
    }

    /// Reads a protection from `metadata.woodcase.textDecoration`: an object of exactly a
    /// string `text` and the booleans `underline` and `strikethrough`.
    ///
    /// - Parameter value: The stored value.
    /// - Throws: ``PenTextSpans/WireError`` naming the first thing that is not the stored form.
    public init(metadataValue value: AnyCodable) throws(PenTextSpans.WireError) {
        guard case let .dictionary(object) = value else {
            throw PenTextSpans.WireError(reason: "text decoration is an object, \(Self.wireForm)")
        }
        if let extra = object.keys.sorted().first(where: { WireKey(rawValue: $0) == nil }) {
            throw PenTextSpans.WireError(reason: "text decoration has an unknown key \"\(extra)\"; it holds \(Self.wireForm)")
        }
        guard case let .string(text)? = object[WireKey.text.rawValue] else {
            throw PenTextSpans.WireError(reason: "text decoration needs text: the content it was made for")
        }
        guard case let .bool(underline)? = object[WireKey.underline.rawValue],
              case let .bool(strikethrough)? = object[WireKey.strikethrough.rawValue]
        else { throw PenTextSpans.WireError(reason: "text decoration needs underline and strikethrough: true or false") }
        self.init(text: text, underline: underline, strikethrough: strikethrough)
    }

    /// The protection in its stored form.
    public var metadataValue: AnyCodable {
        .dictionary([
            WireKey.text.rawValue: .string(text),
            WireKey.underline.rawValue: .bool(underline),
            WireKey.strikethrough.rawValue: .bool(strikethrough),
        ])
    }
}
