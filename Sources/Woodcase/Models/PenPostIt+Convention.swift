//
//  PenPostIt+Convention.swift
//  Woodcase
//

import Foundation

/// The post-it metadata convention: the keys a note's `metadata.woodcase` carries and
/// the spellings the typed ones take.
///
/// Every `note` is a post-it. Pen keeps arbitrary metadata keys, so the convention
/// lives under ``PenMetadata/woodcaseNamespace`` rather than in properties of its own;
/// see <doc:PenPostItConvention> and <doc:PenMetadataNamespace>.
public extension PenPostIt {
    /// The `metadata.type` that marked a node as a post-it before the namespace; read as
    /// `woodcase.type: postit`.
    static let typeValue = "postit"

    /// The convention's keys: the note keys and a note's text style, in
    /// ``PenMetadata/WoodcaseKey`` order.
    static let keys: [PenMetadata.WoodcaseKey] = PenMetadata.WoodcaseKey.allCases.filter {
        $0.group == .note || $0.group == .noteTextStyle
    }

    /// What a note is, as `woodcase.type` spells it.
    enum NoteType: String, Friendly, CaseIterable {
        /// A post-it: a note on the board. A note with no type is one too.
        case postit
        /// One message of a comment thread.
        case comment
    }

    /// Whether a comment thread still asks for attention, as its first message's
    /// `woodcase.state` spells it.
    ///
    /// Only comments have this state (Ben's ruling, 2026-10-11): resolving is how a
    /// conversation ends. A plain note has none — a `state` one still carries is not drawn,
    /// and `woodcase lint` names it (``LintCheck/noteState``) — and a prompt's is a
    /// ``RunState``.
    enum State: String, Friendly, CaseIterable {
        /// The thread still asks for attention.
        case open
        /// The thread is dealt with and kept for the record.
        case resolved
    }

    /// How ``PenMetadata/WoodcaseKey/tint`` is spelled: a `#` and six hex digits.
    static let tintForm = "#RRGGBB"

    /// Parses a tint as the convention spells it.
    ///
    /// - Parameter text: The value of `metadata.woodcase.tint`.
    /// - Returns: The color, or `nil` unless `text` is `#` and exactly six hex digits.
    static func tint(_ text: String) -> PenHexColor? {
        guard text.count == 7, text.hasPrefix("#") else { return nil }
        return PenHexColor(text)
    }
}
