//
//  PenPostIt+Convention.swift
//  Woodcase
//

import Foundation

/// The post-it metadata convention: the keys a post-it's `metadata` carries and the
/// spellings the typed ones take.
///
/// A node is a post-it under the convention when its `metadata.type` is
/// ``typeValue``. Pen keeps arbitrary metadata keys, so the convention lives there
/// rather than in properties of its own; see <doc:PenPostItConvention>.
public extension PenPostIt {
    /// The `metadata.type` that marks a node as a post-it under the convention.
    static let typeValue = "postit"

    /// A key of a post-it's metadata object.
    enum Key: String, Friendly, CaseIterable {
        /// Always ``PenPostIt/typeValue``; what marks the metadata as a post-it's.
        case type
        /// What the post-it is for: one of ``PenPostIt/Kind``.
        case kind
        /// Whether the post-it still asks for attention: one of ``PenPostIt/State``.
        case state
        /// Who wrote the post-it: its creator, or whoever first edited a copy of it.
        case author
        /// The task the post-it belongs to, such as a `job` id.
        case leaf
        /// The part of the work, or the board lane, the post-it sits in.
        case stage
        /// The post-it's paper color, as `#RRGGBB`; absent means Post-it yellow.
        case tint
        /// The original author of a copied post-it, until the copier first edits it.
        ///
        /// A copy keeps ``author`` and sets this; the first edit by the copier replaces
        /// ``author`` with the editor's identity and clears this key (Ben's ruling of
        /// 2026-10-04 on R10's "whoever edited it after copying").
        case copiedFrom

        /// The values this key takes, spelled as the file writes them; empty for a key
        /// that takes any string.
        public var spellings: [String] {
            switch self {
            case .type: [PenPostIt.typeValue]
            case .kind: Kind.allCases.map(\.rawValue)
            case .state: State.allCases.map(\.rawValue)
            case .tint: [PenPostIt.tintForm]
            case .author, .leaf, .stage, .copiedFrom: []
            }
        }

        /// One sentence saying what the key holds.
        public var summary: String {
            switch self {
            case .type: "Marks the metadata as a post-it's."
            case .kind: "What the post-it is for."
            case .state: "Whether it still asks for attention; a resolved post-it draws faded."
            case .author: "Who wrote it: the creator, or whoever first edited a copy."
            case .leaf: "The task it belongs to, such as a job id."
            case .stage: "The part of the work, or the board lane, it sits in."
            case .tint: "The paper color; absent is Post-it yellow."
            case .copiedFrom: "On a copy, the original author, until the copier first edits it."
            }
        }
    }

    /// What a post-it is for.
    enum Kind: String, Friendly, CaseIterable {
        /// A question that wants an answer.
        case question
        /// An answer to a question.
        case answer
        /// Background a reader should know: a reason, a finding, a pointer.
        case reference
    }

    /// Whether a post-it still asks for attention.
    enum State: String, Friendly, CaseIterable {
        /// Still asks for attention.
        case open
        /// Dealt with; kept for the record and drawn faded.
        case resolved
    }

    /// How ``Key/tint`` is spelled: a `#` and six hex digits.
    static let tintForm = "#RRGGBB"

    /// Parses a tint as the convention spells it.
    ///
    /// - Parameter text: The value of `metadata.tint`.
    /// - Returns: The color, or `nil` unless `text` is `#` and exactly six hex digits.
    static func tint(_ text: String) -> PenHexColor? {
        guard text.count == 7, text.hasPrefix("#") else { return nil }
        return PenHexColor(text)
    }
}
