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
        /// Whether a comment thread still asks for attention (open or resolved), or where a
        /// prompt's run stands. A plain note has no state.
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
        /// On a prompt, who pressed Run: the identity that queued its work.
        case requestedBy
        /// On a comment message, when it was written: ISO 8601 in UTC, to the second
        /// (`2026-10-11T20:41:07Z`). An edit to the text never changes it.
        case createdAt

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

        // MARK: A text node's rich text

        /// A text node's styled runs and the content they were made for
        /// (``PenTextSpans``, read and written as ``PenMetadata/textSpans``).
        case spans
        /// A text node's underline and strikethrough, kept where Pen cannot strip them, and
        /// the content they were made for (``PenTextDecoration``).
        case textDecoration

        // MARK: A stroke's dash

        /// The alternating dash and gap lengths a stroke is drawn with, in points
        /// (``PenStrokeDash``). The format has had no dash since 2.17.
        case strokeDash
        /// How far into its dash pattern a stroke starts, in points.
        case strokeDashOffset
        /// The longest a mitered join may reach, as a multiple of the stroke's width, before
        /// it is beveled. The format has had no miter control since 2.17.
        case strokeMiterLimit

        // MARK: A shadow's spread

        /// How far each shadow is grown (or, negative, shrunk) before it is cast, addressed
        /// to its effect by place and holding the shadow it was made for
        /// (``PenShadowSpread``). Format 2.19 dropped `spread`.
        case shadowSpread

        // MARK: A node's blend mode

        /// How the node, drawn as one isolated group, composites onto what lies beneath it
        /// (``PenNode/blendMode``), written and read at the natural path `kind.blendMode`.
        /// Pen's format puts a blend mode only on paints and shadows, and Pen drops a node's
        /// top-level `blendMode` on load.
        case blendMode

        // MARK: Editor state

        /// Whether the node is locked: an editor will not select or hit it on the canvas,
        /// only in its layer list. The format has no lock; Pen keeps the key and ignores it.
        case locked
        /// Whether the text is the document's default text style: an editor styles a new text
        /// like the first marked text in document order, live (Penumbra spec §6.3, Ben's ruling
        /// of 2026-10-18). The format has no document-level metadata; Pen keeps the key and
        /// ignores it. Only a text's mark counts.
        case defaultTextStyle

        /// Which part of Woodcase a key belongs to.
        public enum Group: String, Friendly, CaseIterable {
            /// Read by code generation and its lints.
            case codegen
            /// The note, post-it and comment convention.
            case note
            /// A note's text style, which Pen strips from the node itself.
            case noteTextStyle
            /// A text node's rich text and protected decoration, which Pen strips or cannot hold.
            case text
            /// A shape's stroke dash and miter limit, which Pen's format cannot hold.
            case stroke
            /// How an editor treats the node — a lock, the default text style — which Pen's format
            /// cannot hold.
            case editor
            /// A node's shadow spreads, which Pen's format cannot hold.
            case effect
            /// How a node as a whole composites onto what lies beneath it, which Pen's format
            /// cannot hold.
            case compositing
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
            /// A text node's spans: `{text, runs: [{start, end, …}]}`, as
            /// ``PenTextSpans/init(metadataValue:)`` reads them.
            case textSpans
            /// A time in UTC, to the second, as ``PenComment/date(createdAt:)`` reads it.
            case utcTimestamp
            /// A stroke's dash lengths: an array of numbers, as
            /// ``PenStrokeDash/problem(in:)`` holds them.
            case dashLengths
            /// `true` or `false`.
            case boolean
            /// A text's protected decoration: `{text, underline, strikethrough}`, as
            /// ``PenTextDecoration/init(metadataValue:)`` reads it.
            case textDecoration
            /// A node's shadow spreads: `[{effect, spread, shadow}]`, as
            /// ``PenShadowSpread/entries(in:)`` reads them.
            case shadowSpreads
        }

        /// Which part of Woodcase the key belongs to.
        public var group: Group {
            switch self {
            case .props, .role, .states, .action, .scroll: .codegen
            case .type, .state, .author, .leaf, .stage, .tint, .copiedFrom, .anchor, .replyTo, .requestedBy, .createdAt:
                .note
            case .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing, .lineHeight, .textAlign,
                 .textAlignVertical: .noteTextStyle
            case .spans, .textDecoration: .text
            case .strokeDash, .strokeDashOffset, .strokeMiterLimit: .stroke
            case .shadowSpread: .effect
            case .blendMode: .compositing
            case .locked, .defaultTextStyle: .editor
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
            case .anchor, .replyTo, .requestedBy, .createdAt, .fontFamily, .fontSize, .fontWeight, .fontStyle, .letterSpacing,
                 .lineHeight, .textAlign, .textAlignVertical, .spans, .textDecoration, .strokeDash, .strokeDashOffset,
                 .strokeMiterLimit, .shadowSpread, .blendMode, .locked, .defaultTextStyle: nil
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
            // Any string, as `kind.blendMode` takes: a mode Woodcase does not know is kept.
            case .author, .leaf, .stage, .copiedFrom, .replyTo, .requestedBy, .fontFamily, .fontWeight, .fontStyle,
                 .blendMode:
                .string
            case .fontSize, .letterSpacing, .lineHeight, .strokeDashOffset, .strokeMiterLimit: .number
            case .spans: .textSpans
            case .textDecoration: .textDecoration
            case .strokeDash: .dashLengths
            case .shadowSpread: .shadowSpreads
            case .createdAt: .utcTimestamp
            case .locked, .defaultTextStyle: .boolean
            }
        }

        /// What an authored value must be on a node of `kind`: ``shape``, except that a
        /// prompt's ``state`` is a run state (``PenPostIt/RunState``) — Run queues work in
        /// the file — where every other node's is ``PenPostIt/State``, a comment's.
        ///
        /// - Parameter kind: The kind of the node the value is written to.
        /// - Returns: The shape the value is held to.
        func shape(on kind: PenNode.Kind) -> Shape {
            guard self == .state, case .prompt = kind else { return shape }
            return .oneOf(PenPostIt.RunState.allCases.map(\.rawValue))
        }

        /// The values the key takes, spelled as the file writes them; empty for a key
        /// that takes any value of its kind.
        public var spellings: [String] {
            switch shape {
            case let .oneOf(spellings): spellings
            case .hexColor: [PenPostIt.tintForm]
            case .textSpans: [PenTextSpans.wireForm]
            case .utcTimestamp: [PenComment.createdAtForm]
            case .boolean: ["true", "false"]
            case .shadowSpreads: [PenShadowSpread.wireForm]
            case .textDecoration: [PenTextDecoration.wireForm]
            case .any, .string, .number, .dashLengths: []
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
            case .state: "A comment thread's: open or resolved. A prompt's: queued, running or done. A plain note has none."
            case .author: "Who wrote it: the creator, or whoever first edited a copy."
            case .leaf: "The task it belongs to, such as a job id."
            case .stage: "The part of the work, or the board lane, it sits in."
            case .tint: "The paper color; absent is Post-it yellow."
            case .copiedFrom: "On a copy, the original author, until the copier first edits it."
            case .anchor: "On a comment's first message, the node and point it is about."
            case .replyTo: "On a comment reply, the id of the thread's first message."
            case .requestedBy: "On a prompt, who pressed Run."
            case .createdAt: "On a comment message, when it was written: ISO 8601 UTC, to the second."
            case .fontFamily: "The note's font family."
            case .fontSize: "The note's font size, in points."
            case .fontWeight: "The note's font weight."
            case .fontStyle: "The note's font style."
            case .letterSpacing: "Extra space between glyphs, in points."
            case .lineHeight: "The line height, as a multiple of the font size."
            case .textAlign: "The horizontal alignment of the note's lines."
            case .textAlignVertical: "The vertical alignment of the note's text."
            case .spans: "A text node's styled runs, and the content they were made for."
            case .textDecoration: "A text's underline and strikethrough, kept from Pen, and the content they were made for."
            case .strokeDash: "The stroke's alternating dash and gap lengths, in points; absent or empty is solid."
            case .strokeDashOffset: "How far into its dash pattern the stroke starts, in points."
            case .locked: "Whether an editor keeps the node from being selected on the canvas; absent is unlocked."
            case .defaultTextStyle: "Whether a text is the document's default text style; the first marked text wins."
            case .strokeMiterLimit: "The longest a mitered join reaches, in stroke widths, before it is beveled; absent is Pen's 4."
            case .shadowSpread: "How far each shadow is grown before it is cast, per effect, and the shadow it was made for."
            case .blendMode: "How the node as a whole blends with what lies beneath it; absent is normal. Write kind.blendMode."
            }
        }

        /// The key's property path for a deep-key write, such as
        /// `common.metadata.woodcase.tint`.
        public var path: String {
            "common.metadata.\(PenMetadata.woodcaseNamespace).\(rawValue)"
        }
    }
}
