//
//  PenNode+NoteTextStyleSource.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// Where the value a note's text is drawn with for one text-style key comes from.
    ///
    /// ``noteTextStyle`` reads each key from three places in turn; this names the one
    /// that supplied it, so an inspector can say where a value lives — a legacy note's
    /// 18 pt is its own `kind.fontSize`, which Pen strips on load, not its metadata.
    enum NoteTextStyleSource: String, Friendly, CaseIterable {
        /// The note's `metadata.woodcase` (`common.metadata.woodcase.fontSize`).
        case metadata
        /// The note's own property (`kind.fontSize`), which a file Pen has not loaded
        /// may still carry.
        case property
        /// Neither: the post-it default (``PenPostIt/defaultFontSize``,
        /// ``PenPostIt/defaultLineHeight``) or ``PenTextStyle``'s.
        case `default`
    }

    /// Where the value a note's text is drawn with for `key` comes from.
    ///
    /// Agrees with ``noteTextStyle`` by construction — both read through the same rules —
    /// so a value the drawing skips (a type size of 0, a misspelled alignment, a string
    /// where a number belongs) is never named as the source.
    ///
    /// ```swift
    /// legacyNote.noteTextStyleSource(of: .fontSize)  // .property
    /// ```
    ///
    /// - Parameter key: A text-style key (``PenMetadata/WoodcaseKey/Group/noteTextStyle``).
    /// - Returns: The source, or `nil` for a key outside that group or a node that is not
    ///   a note, prompt or context.
    func noteTextStyleSource(of key: PenMetadata.WoodcaseKey) -> NoteTextStyleSource? {
        guard key.group == .noteTextStyle, let reading = noteTextStyleReading else { return nil }
        if reading.metadataSupplies(key) { return .metadata }
        return reading.propertySupplies(key) ? .property : .default
    }
}

extension PenNode {
    /// A note's text-style keys as its drawing reads them: one set of rules for what
    /// counts as written, shared by ``noteTextStyle`` and ``noteTextStyleSource(of:)``.
    struct NoteTextStyleReading {
        /// The note's metadata, or an empty one.
        let metadata: PenMetadata

        /// The note's own text-style properties.
        let data: any PenTextStyleProperties

        /// A metadata number the drawing uses: finite, and for the type size and the look
        /// scale above 0.
        func number(_ key: PenMetadata.WoodcaseKey) -> Double? {
            let value: Double? = switch metadata[woodcase: key] {
            case let .int(value)?: Double(value)
            case let .double(value)? where value.isFinite: value
            default: nil
            }
            guard key == .fontSize || key == .scale else { return value }
            return value.flatMap { $0 > 0 ? $0 : nil }
        }

        /// A metadata string the drawing uses: a weight may be a number, and an alignment
        /// must be one of its spellings.
        func string(_ key: PenMetadata.WoodcaseKey) -> String? {
            let value: String? = switch metadata[woodcase: key] {
            case let .string(value)?: value
            case let .int(value)? where key == .fontWeight: String(value)
            case let .double(value)? where key == .fontWeight: String(value)
            default: nil
            }
            switch key {
            case .textAlign: return value.flatMap(PenTextAlign.init(rawValue:))?.rawValue
            case .textAlignVertical: return value.flatMap(PenTextAlignVertical.init(rawValue:))?.rawValue
            default: return value
            }
        }

        /// The note's own type size, when it is a literal above 0.
        var ownFontSize: Double? {
            data.fontSize?.literalValue.flatMap { $0 > 0 ? $0 : nil }
        }

        /// Whether the metadata supplies the value drawn for `key`.
        func metadataSupplies(_ key: PenMetadata.WoodcaseKey) -> Bool {
            switch key {
            case .fontSize, .lineHeight, .letterSpacing, .scale: number(key) != nil
            default: string(key) != nil
            }
        }

        /// Whether the note's own property supplies the value drawn for `key`, once the
        /// metadata does not. Only a literal counts, as ``PenTextStyle/init(_:)`` reads it.
        func propertySupplies(_ key: PenMetadata.WoodcaseKey) -> Bool {
            switch key {
            case .fontFamily: data.fontFamily?.literalValue != nil
            case .fontSize: ownFontSize != nil
            case .fontWeight: data.fontWeight?.literalValue != nil
            case .fontStyle: data.fontStyle?.literalValue != nil
            case .letterSpacing: data.letterSpacing?.literalValue != nil
            case .lineHeight: data.lineHeight?.literalValue != nil
            case .textAlign: data.textAlign != nil
            case .textAlignVertical: data.textAlignVertical != nil
            default: false
            }
        }
    }

    /// The reading of a note's, prompt's or context's text style, or `nil` for any other
    /// node.
    var noteTextStyleReading: NoteTextStyleReading? {
        let data: any PenTextStyleProperties
        switch kind {
        case let .note(note): data = note
        case let .prompt(prompt): data = prompt
        case let .context(context): data = context
        default: return nil
        }
        return NoteTextStyleReading(metadata: common.metadata ?? PenMetadata(type: nil), data: data)
    }
}
