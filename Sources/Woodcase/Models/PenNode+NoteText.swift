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
    /// the same way.
    var noteTextStyle: PenTextStyle? {
        let data: any PenTextStyleProperties
        switch kind {
        case let .note(note): data = note
        case let .prompt(prompt): data = prompt
        case let .context(context): data = context
        default: return nil
        }
        let metadata = common.metadata ?? PenMetadata(type: nil)
        func number(_ key: PenMetadata.WoodcaseKey) -> Double? {
            switch metadata[woodcase: key] {
            case let .int(value)?: Double(value)
            case let .double(value)? where value.isFinite: value
            default: nil
            }
        }
        func string(_ key: PenMetadata.WoodcaseKey) -> String? {
            switch metadata[woodcase: key] {
            case let .string(value)?: value
            case let .int(value)? where key == .fontWeight: String(value)
            case let .double(value)? where key == .fontWeight: String(value)
            default: nil
            }
        }
        let own = PenTextStyle(data)
        return PenTextStyle(
            fontFamily: string(.fontFamily) ?? own.fontFamily,
            fontSize: number(.fontSize).flatMap { $0 > 0 ? $0 : nil }
                ?? data.fontSize?.literalValue.flatMap { $0 > 0 ? $0 : nil } ?? PenPostIt.defaultFontSize,
            fontWeight: string(.fontWeight).map(PenTextStyle.weight) ?? own.fontWeight,
            isItalic: string(.fontStyle).map(PenTextStyle.isItalic) ?? own.isItalic,
            letterSpacing: number(.letterSpacing) ?? own.letterSpacing,
            lineHeight: number(.lineHeight) ?? own.lineHeight ?? PenPostIt.defaultLineHeight,
            textAlign: string(.textAlign).flatMap(PenTextAlign.init(rawValue:)) ?? own.textAlign,
            textAlignVertical: string(.textAlignVertical).flatMap(PenTextAlignVertical.init(rawValue:))
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
