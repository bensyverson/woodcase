//
//  PenNode+NoteText.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The style a note's text is set in, or `nil` for a node that is not a note, prompt
    /// or context.
    ///
    /// Pen strips a note's own text style when it loads a file, so the style lives in
    /// `metadata.woodcase` (``PenMetadata/WoodcaseKey/Group/noteTextStyle``). Each key is
    /// read from there first, then from the note's own property (a file Pen has not
    /// loaded may still carry one), then takes the default: ``PenPostIt/defaultFontSize``
    /// at ``PenPostIt/defaultLineHeight`` — the rev 2 look's 13 points at 1.35 — and
    /// ``PenTextStyle``'s default for every other key. A metadata value of the wrong JSON
    /// type, or a misspelled alignment, is skipped as if absent. Comments are notes, and
    /// prompts and contexts are drawn as cards in the same family, so all of them read
    /// the same way. ``noteTextStyleSource(of:)`` says which of the three supplied a key.
    var noteTextStyle: PenTextStyle? {
        guard let reading = noteTextStyleReading else { return nil }
        let own = PenTextStyle(reading.data)
        return PenTextStyle(
            fontFamily: reading.string(.fontFamily) ?? own.fontFamily,
            fontSize: reading.number(.fontSize) ?? reading.ownFontSize ?? PenPostIt.defaultFontSize,
            fontWeight: reading.string(.fontWeight).map(PenTextStyle.weight) ?? own.fontWeight,
            isItalic: reading.string(.fontStyle).map(PenTextStyle.isItalic) ?? own.isItalic,
            letterSpacing: reading.number(.letterSpacing) ?? own.letterSpacing,
            lineHeight: reading.number(.lineHeight) ?? own.lineHeight ?? PenPostIt.defaultLineHeight,
            textAlign: reading.string(.textAlign).flatMap(PenTextAlign.init(rawValue:)) ?? own.textAlign,
            textAlignVertical: reading.string(.textAlignVertical).flatMap(PenTextAlignVertical.init(rawValue:))
                ?? own.textAlignVertical,
            underline: own.underline,
            strikethrough: own.strikethrough
        )
    }

    /// A note's, prompt's or context's `content` parsed as markdown at its font size, or
    /// `nil` for another node, or one whose content is absent or an unresolved `$variable`.
    ///
    /// Derived on every read and never stored: the file keeps only the markdown.
    var noteMarkdown: PenNoteMarkdown? {
        guard let source = noteSource, let style = noteTextStyle else { return nil }
        return PenNoteMarkdown(source, fontSize: style.fontSize)
    }

    /// A note's, prompt's or context's `content` as written — its markdown source — or
    /// `nil` for another node, or one whose content is absent or an unresolved `$variable`.
    internal var noteSource: String? {
        let content: PenValue<String>? = switch kind {
        case let .note(data): data.content
        case let .prompt(data): data.content
        case let .context(data): data.content
        default: nil
        }
        return content?.literalValue
    }
}
