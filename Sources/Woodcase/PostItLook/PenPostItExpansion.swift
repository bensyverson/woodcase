//
//  PenPostItExpansion.swift
//  Woodcase
//

import Foundation

/// A note, prompt or context expanded into the parts every renderer draws: the single
/// source of the rev 2 look.
///
/// ``PenPostIt/expansion(of:width:height:style:measure:)`` makes one from a node and its
/// laid-out size. Woodcase's CG renderer draws it, and RapidPro draws the same parts, so
/// the look is decided once, here, and a renderer only paints: shapes through their node
/// (``Shape/node(id:frame:)``), which every renderer already draws, and text through
/// ``PenTextLayout``, which every renderer already sets text with. See
/// <doc:PenPostItLook>.
///
/// Every frame is in the node's own coordinates — origin at its top-left, unturned — so a
/// renderer draws the parts inside the node's placement, as it draws a frame's children.
/// The parts are in paint order. Two kinds of facts ride beside them for an editor that
/// knows more than Woodcase: who the note is by (``identity``) and whom it mentions
/// (``mentions``), so it can repaint the dot and draw the mention pills in presence colors.
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
    /// The body's mentions: a range of the ``Role/body`` text and the name it mentions.
    public var mentions: [Mention]
    /// The author whose dot is drawn, and the fallback color it is drawn in; `nil` when no
    /// author is drawn.
    public var identity: Identity?

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
    public init(
        variant: PenPostIt.Variant, width: Double, height: Double, ink: PenPostIt.Ink,
        parts: [Part], mentions: [Mention] = [], identity: Identity? = nil
    ) {
        self.variant = variant
        self.width = width
        self.height = height
        self.ink = ink
        self.parts = parts
        self.mentions = mentions
        self.identity = identity
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
        /// The author's identity dot, at the bottom left of a note.
        case identityDot
        /// The author's name, beside the dot.
        case author
        /// "Resolved", at the bottom right of a resolved note.
        case resolvedLabel
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

    /// One mention in the body: an editor draws it as a pill in the person's identity
    /// color. The CG renderer, which knows no identity colors, draws it as the bold ink
    /// its run sets.
    public struct Mention: Friendly {
        /// The mention's UTF-16 range in the ``Role/body`` part's text, `@` included.
        public var range: Range<Int>
        /// Who is mentioned: `claude` for `@claude`.
        public var name: String

        /// Creates a mention.
        ///
        /// - Parameters:
        ///   - range: Its UTF-16 range in the body's text.
        ///   - name: Who is mentioned.
        public init(range: Range<Int>, name: String) {
            self.range = range
            self.name = name
        }
    }

    /// The author an expansion draws a dot for.
    public struct Identity: Friendly {
        /// The author, as `woodcase.author` spells it, never cut.
        public var author: String
        /// The fallback color the dot is drawn in (``PenPostIt/identityColor(for:style:)``).
        public var color: PenHexColor

        /// Creates an identity.
        ///
        /// - Parameters:
        ///   - author: The author.
        ///   - color: The dot's fallback color.
        public init(author: String, color: PenHexColor) {
            self.author = author
            self.color = color
        }
    }
}
