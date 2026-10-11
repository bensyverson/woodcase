//
//  PenMetadata+WoodcaseKey.swift
//  Woodcase
//

import Foundation

public extension PenMetadata {
    /// The key of a node's metadata object that holds everything Woodcase owns there.
    ///
    /// Pen keeps every metadata key, nested values included, so one object under one
    /// key says whose the keys are and cannot collide with anyone else's metadata. See
    /// <doc:PenMetadataNamespace>.
    static let woodcaseNamespace = "woodcase"

    /// The `metadata.type` Woodcase writes when a metadata object it writes has none.
    ///
    /// Pen's schema requires `type` on every metadata object
    /// (`metadata?: { type: string; [key: string]: any }`), so Woodcase never leaves one
    /// without: an object it creates, and a post-it's old `type: "postit"`, take this
    /// value. A `type` anyone else wrote is never touched (Ben's ruling, 2026-10-11).
    static let woodcaseType = "woodcase"

    /// A key Woodcase owns inside `metadata.woodcase`.
    ///
    /// Read and write one through ``PenMetadata/subscript(woodcase:)``, never through
    /// the raw ``PenMetadata/extensions``: the subscript is what reads a key's old
    /// spelling, lets the namespace win, and removes the old spelling on a write.
    ///
    /// **Adding a key** is one case here: give it its ``group``, its ``shape`` (what
    /// an authored write is held to), a ``summary``, and an ``oldSpelling`` only if
    /// files written before the namespace carry it. Everything else — reading,
    /// writing, the authoring check, `woodcase schema postit`, the
    /// `metadata-old-style` lint and `woodcase migrate` — follows from that.
    enum WoodcaseKey: String, Friendly, CaseIterable {
        // MARK: Code generation

        /// A component's published parameters: name → a name path to one descendant.
        case props
        /// The semantic role a node plays in generated code, such as `button`.
        case role
        /// A component's state variants: state name → the id of the variant node.
        case states
        /// The action an interactive node fires in generated code.
        case action
        /// The axis a clipping frame scrolls along: `vertical` or `horizontal`.
        case scroll

        // MARK: Notes and comments

        /// What the note is: a post-it, or one message of a comment thread.
        case type
        /// Whether a post-it or a comment thread still asks for attention.
        case state
        /// Who wrote the note: its creator, or whoever first edited a copy of it.
        case author
        /// The task the note belongs to, such as a `job` id.
        case leaf
        /// The part of the work, or the board lane, the note sits in.
        case stage
        /// The note's paper color, as `#RRGGBB`; absent means Post-it yellow.
        case tint
        /// On a copy, the original author, until the copier first edits it.
        case copiedFrom
        /// On a comment thread's first message, the node and the point on it the
        /// comment is about.
        case anchor
        /// On a comment reply, the id of the thread's first message.
        case replyTo

        // MARK: A note's text style

        /// The note's font family. Pen strips a note's own text style, so it lives here.
        case fontFamily
        /// The note's font size in points.
        case fontSize
        /// The note's font weight, as Pen spells it.
        case fontWeight
        /// The note's font style: `normal` or `italic`.
        case fontStyle
        /// Extra space between glyphs in the note, in points.
        case letterSpacing
        /// The note's line height, as a multiple of its font size.
        case lineHeight
        /// The horizontal alignment of the note's lines.
        case textAlign
        /// The vertical alignment of the note's text.
        case textAlignVertical

        /// Which part of Woodcase a key belongs to.
        public enum Group: String, Friendly, CaseIterable {
            /// Read by code generation and its lints.
            case codegen
            /// The note, post-it and comment convention.
            case note
            /// A note's text style, which Pen strips from the node itself.
            case noteTextStyle
        }

        /// What an authored value of a key must be.
        public enum Shape: Friendly {
            /// Any JSON; the key is checked elsewhere, or not at all.
            case any
            /// Any string.
            case string
            /// Any number.
            case number
            /// One of these strings.
            case oneOf([String])
            /// `#` and six hex digits.
            case hexColor
        }

        /// Which part of Woodcase the key belongs to.
        public var group: Group {
            switch self {
            case .props, .role, .states, .action, .scroll: .codegen
            case .type, .state, .author, .leaf, .stage, .tint, .copiedFrom, .anchor, .replyTo: .note
            case .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing, .lineHeight, .textAlign,
                 .textAlignVertical: .noteTextStyle
            }
        }

        /// The key's spelling before the namespace, or `nil` for a key that never had one.
        ///
        /// A code-gen key's old spelling is read wherever it appears. A note key's old
        /// spelling — bare, beside `type` — is read only on metadata that is a post-it's
        /// under the old convention (`type: "postit"`), or that names its type in the
        /// namespace; anywhere else a bare `author` is someone else's key.
        public var oldSpelling: String? {
            switch self {
            case .props, .role, .states, .action, .scroll: "_\(rawValue)"
            case .type, .state, .author, .leaf, .stage, .tint, .copiedFrom: rawValue
            case .anchor, .replyTo, .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing,
                 .lineHeight, .textAlign, .textAlignVertical: nil
            }
        }

        /// What an authored value must be; a file is never held to it.
        public var shape: Shape {
            switch self {
            case .props, .role, .states, .action, .scroll, .anchor: .any
            case .type: .oneOf(PenPostIt.NoteType.allCases.map(\.rawValue))
            case .state: .oneOf(PenPostIt.State.allCases.map(\.rawValue))
            case .textAlign: .oneOf(PenTextAlign.allCases.map(\.rawValue))
            case .textAlignVertical: .oneOf(PenTextAlignVertical.allCases.map(\.rawValue))
            case .tint: .hexColor
            case .author, .leaf, .stage, .copiedFrom, .replyTo, .fontFamily, .fontWeight, .fontStyle: .string
            case .fontSize, .letterSpacing, .lineHeight: .number
            }
        }

        /// The values the key takes, spelled as the file writes them; empty for a key
        /// that takes any value of its kind.
        public var spellings: [String] {
            switch shape {
            case let .oneOf(spellings): spellings
            case .hexColor: [PenPostIt.tintForm]
            case .any, .string, .number: []
            }
        }

        /// One sentence saying what the key holds.
        public var summary: String {
            switch self {
            case .props: "The parameters a component publishes: name to a name path."
            case .role: "The role a node plays in generated code."
            case .states: "A component's state variants: state name to variant node id."
            case .action: "The action an interactive node fires in generated code."
            case .scroll: "The axis a clipping frame scrolls along."
            case .type: "What the note is: a post-it, or a comment message."
            case .state: "Whether it still asks for attention; a resolved post-it draws faded."
            case .author: "Who wrote it: the creator, or whoever first edited a copy."
            case .leaf: "The task it belongs to, such as a job id."
            case .stage: "The part of the work, or the board lane, it sits in."
            case .tint: "The paper color; absent is Post-it yellow."
            case .copiedFrom: "On a copy, the original author, until the copier first edits it."
            case .anchor: "On a comment's first message, the node and point it is about."
            case .replyTo: "On a comment reply, the id of the thread's first message."
            case .fontFamily: "The note's font family."
            case .fontSize: "The note's font size, in points."
            case .fontWeight: "The note's font weight."
            case .fontStyle: "The note's font style."
            case .letterSpacing: "Extra space between glyphs, in points."
            case .lineHeight: "The line height, as a multiple of the font size."
            case .textAlign: "The horizontal alignment of the note's lines."
            case .textAlignVertical: "The vertical alignment of the note's text."
            }
        }

        /// The key's property path for a deep-key write, such as
        /// `common.metadata.woodcase.tint`.
        public var path: String {
            "common.metadata.\(PenMetadata.woodcaseNamespace).\(rawValue)"
        }
    }
}
