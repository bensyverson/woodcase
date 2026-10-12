//
//  PenPostItExpansion.swift
//  Woodcase
//

import Foundation

/// A note, prompt or context expanded into the parts every renderer draws: the single
/// source of the rev 2 look.
///
/// ``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:)`` makes one from a node and its
/// laid-out size. Woodcase's CG renderer draws it, and RapidPro draws the same parts, so
/// the look is decided once, here, and a renderer only paints: shapes through their node
/// (``Shape/node(id:frame:)``), which every renderer already draws, and text through
/// ``PenTextLayout``, which every renderer already sets text with. See
/// <doc:PenPostItLook>.
///
/// Every frame is in the node's own coordinates — origin at its top-left, unturned — so a
/// renderer draws the parts inside the node's placement, as it draws a frame's children.
/// The parts are in paint order. Facts ride beside them for an editor: who the note is by
/// (``identity``), whom it mentions (``mentions``), and where each checklist box is
/// (``checkboxes``), so a click can toggle it. The identity colors are already in the parts —
/// the caller's, or ``ActorColor``'s hash.
public struct PenPostItExpansion: Friendly {
    /// Which card this is.
    public var variant: PenPostIt.Variant
    /// The node's laid-out width.
    public var width: Double
    /// The node's laid-out height, grown to fit its text.
    public var height: Double
    /// The inks its text is written in, chosen by its paper.
    public var ink: PenPostIt.Ink
    /// The parts, in paint order.
    public var parts: [Part]
    /// The body's mentions: a range of the ``Role/body`` text, the name it mentions, and
    /// the color its pill is drawn in.
    public var mentions: [Mention]
    /// The author whose dot is drawn, and the color it is drawn in; `nil` when no author is
    /// drawn.
    public var identity: Identity?
    /// The body's checklist boxes, in order, each with the rect a click toggles it in.
    public var checkboxes: [Checkbox]

    /// Creates an expansion.
    ///
    /// - Parameters:
    ///   - variant: Which card it is.
    ///   - width: The node's laid-out width.
    ///   - height: The node's laid-out height.
    ///   - ink: The inks its text is written in.
    ///   - parts: The parts, in paint order.
    ///   - mentions: The body's mentions.
    ///   - identity: The author drawn, if any.
    ///   - checkboxes: The checklist boxes drawn.
    public init(
        variant: PenPostIt.Variant, width: Double, height: Double, ink: PenPostIt.Ink,
        parts: [Part], mentions: [Mention] = [], identity: Identity? = nil, checkboxes: [Checkbox] = []
    ) {
        self.variant = variant
        self.width = width
        self.height = height
        self.ink = ink
        self.parts = parts
        self.mentions = mentions
        self.identity = identity
        self.checkboxes = checkboxes
    }

    /// The first part playing a role.
    ///
    /// - Parameter role: The role.
    /// - Returns: The part, or `nil` when the expansion has none.
    public func part(_ role: Role) -> Part? {
        parts.first { $0.role == role }
    }

    /// The text of the first part playing a role.
    ///
    /// - Parameter role: The role.
    /// - Returns: Its text, or `nil` when the expansion has no such part or it is a shape.
    public func text(_ role: Role) -> Text? {
        guard case let .text(text)? = part(role)?.paint else { return nil }
        return text
    }

    /// One drawable piece: what it is, where, and how it is painted.
    public struct Part: Friendly {
        /// What the part is, so a renderer or an editor can find it.
        public var role: Role
        /// Where it is, in the node's own coordinates.
        public var frame: PenRect
        /// How it is painted.
        public var paint: Paint

        /// Creates a part.
        ///
        /// - Parameters:
        ///   - role: What the part is.
        ///   - frame: Where it is, in the node's own coordinates.
        ///   - paint: How it is painted.
        public init(role: Role, frame: PenRect, paint: Paint) {
            self.role = role
            self.frame = frame
            self.paint = paint
        }
    }

    /// How a part is painted.
    public enum Paint: Friendly {
        /// A filled, edged or shadowed shape.
        case shape(Shape)
        /// A text, set in its frame.
        case text(Text)
    }

    /// What a part is.
    public enum Role: String, Friendly, CaseIterable {
        /// The paper: the whole node, filled, edged and shadowed.
        case plate
        /// The note's text, from its markdown.
        case body
        /// A mention's pill, behind its text, in the person's identity color.
        case mentionPill
        /// A list item's bullet: a dot in the body ink.
        case bullet
        /// A checklist item's box, as tall as the body's cap height; its frame is the
        /// item's hit rect (``PenPostItExpansion/checkboxes``).
        case checkbox
        /// The check mark in a done item's box.
        case checkMark
        /// The author's identity dot, at the bottom left of a note.
        case identityDot
        /// The author's name, beside the dot.
        case author
        /// A card's header: "▶ PROMPT" or "CONTEXT".
        case header
        /// A context's ⓘ ring.
        case infoMark
        /// The "i" inside the ring.
        case infoGlyph
        /// A prompt's model chip.
        case modelChip
        /// The model's name in the chip.
        case modelLabel
        /// The dot colored by a prompt's run state.
        case statusDot
        /// A prompt's run state and who requested it.
        case status
        /// A prompt's Run button.
        case runButton
        /// "▶ Run" on the button.
        case runLabel
    }

    /// One mention in the body, drawn as a ``Role/mentionPill`` part per line it sits on
    /// and lettered in its color's ink by a fill run over ``range``.
    public struct Mention: Friendly {
        /// The mention's UTF-16 range in the ``Role/body`` part's text, `@` included.
        public var range: Range<Int>
        /// Who is mentioned: `claude` for `@claude`.
        public var name: String
        /// The pill's color: the caller's for that identity, or its ``ActorColor``.
        public var color: PenHexColor

        /// Creates a mention.
        ///
        /// - Parameters:
        ///   - range: Its UTF-16 range in the body's text.
        ///   - name: Who is mentioned.
        ///   - color: Its pill's color.
        public init(range: Range<Int>, name: String, color: PenHexColor) {
            self.range = range
            self.name = name
            self.color = color
        }
    }

    /// The author an expansion draws a dot for.
    public struct Identity: Friendly {
        /// The author, as `woodcase.author` spells it, never cut.
        public var author: String
        /// The color the dot is drawn in: the caller's for that identity, or its
        /// ``ActorColor``.
        public var color: PenHexColor

        /// Creates an identity.
        ///
        /// - Parameters:
        ///   - author: The author.
        ///   - color: The dot's color.
        public init(author: String, color: PenHexColor) {
            self.author = author
            self.color = color
        }
    }
}
