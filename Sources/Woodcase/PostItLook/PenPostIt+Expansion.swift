//
//  PenPostIt+Expansion.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// A note, prompt or context expanded into the parts of the rev 2 look.
    ///
    /// A note is tinted paper — `woodcase.tint`, absent or malformed is Post-it yellow —
    /// with its markdown body and, when it names an author, the author's identity dot and
    /// name at the bottom. A note has no state: a `state` it still carries draws nothing
    /// (only comments are open or resolved). A prompt is a white card with its model chip,
    /// ▶ Run and its run's status; a context is a quiet card with an ⓘ mark. No note
    /// carries a kind mark. See <doc:PenPostItLook>.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - width: Its laid-out width.
    ///   - height: Its laid-out height, grown to fit its text.
    ///   - style: The look.
    ///   - measure: The text measurer the chrome's labels are measured with; the layout's.
    ///   - labels: The words for the chrome's labels; English by default. The labels are
    ///     measured as this spells them, so a localized label is fitted, not the English.
    ///   - identityColor: The color a person chose, by identity, or `nil` to draw them in
    ///     their ``ActorColor``. Their dot and their mention pills take it.
    ///   - body: How the body is drawn: styled from its markdown, or raw, as written, for
    ///     a card being edited (``BodyText``). The chrome and the box are the same either
    ///     way.
    /// - Returns: The expansion, or `nil` for a node that is not a note, prompt or context,
    ///   and for a comment message (`woodcase.type: comment`), which Penumbra draws.
    static func expansion(
        of node: PenNode,
        width: Double,
        height: Double,
        style: Style = .standard,
        measure: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer,
        labels: @escaping (Label) -> String = { $0.english },
        identityColor: @escaping (String) -> PenHexColor? = { _ in nil },
        body: BodyText = .styled
    ) -> PenPostItExpansion? {
        guard let variant = Variant(node.kind), let text = node.noteTextStyle else { return nil }
        let metadata = Metadata(node)
        if metadata?.type == .valid(.comment) { return nil }
        let drawing = Drawing(
            chrome: Chrome(style: style, fontSize: text.fontSize), measure: measure, labels: labels,
            identityColors: identityColor, bodyText: body
        )
        let box = (width: width, height: height)
        return switch variant {
        case .note: noteExpansion(node, metadata: metadata, box: box, drawing: drawing)
        case .prompt: promptExpansion(node, metadata: metadata, box: box, drawing: drawing)
        case .context: contextExpansion(node, box: box, drawing: drawing)
        }
    }

    /// A note, prompt or context expanded with a caller's drawing options: its words for
    /// the labels, its identity colors, and whether this node's body is drawn raw
    /// (``DrawingOptions/bodyText(for:)``).
    ///
    /// The one call a renderer makes, so a new option reaches every renderer through the
    /// value it already passes. See
    /// ``expansion(of:width:height:style:measure:labels:identityColor:body:)``.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - width: Its laid-out width.
    ///   - height: Its laid-out height, grown to fit its text.
    ///   - style: The look.
    ///   - measure: The text measurer the chrome's labels are measured with; the layout's.
    ///   - options: The caller's drawing options.
    /// - Returns: The expansion, or `nil` for a node that is not a note, prompt or context,
    ///   and for a comment message.
    static func expansion(
        of node: PenNode,
        width: Double,
        height: Double,
        style: Style = .standard,
        measure: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer,
        options: DrawingOptions
    ) -> PenPostItExpansion? {
        expansion(
            of: node, width: width, height: height, style: style, measure: measure, labels: options.labels,
            identityColor: options.identityColor, body: options.bodyText(for: node.id)
        )
    }
}

extension PenPostIt {
    /// A post-it: its paper, its body, and its author line.
    static func noteExpansion(
        _ node: PenNode, metadata: Metadata?, box: (width: Double, height: Double), drawing: Drawing
    ) -> PenPostItExpansion {
        let style = drawing.style
        let paper = metadata?.tint?.value ?? Tint.default.color
        let ink = Ink(on: paper, style: style)
        var parts = [plate(
            paper, box: box, cornerRadius: style.noteCornerRadius, hairline: style.hairline,
            shadows: style.shadows, style: style
        )]
        let content = body(of: node, box: box, color: ink.primary, ink: ink, paper: paper, drawing: drawing)
        parts += content.parts
        var identity: PenPostItExpansion.Identity?
        if let author = Chrome.author(metadata) {
            let footer = footerParts(author, box: box, ink: ink, drawing: drawing)
            parts += footer.parts
            identity = footer.identity
        }
        return PenPostItExpansion(
            variant: .note, width: box.width, height: box.height, ink: ink,
            parts: parts, mentions: content.mentions, identity: identity, checkboxes: content.checkboxes
        )
    }

    /// The author's dot and name at the bottom left. On dark paper the dot takes a light
    /// ring (``Style/identityRingOnDark``), so a dark hue still reads against it.
    private static func footerParts(
        _ author: String, box: (width: Double, height: Double), ink: Ink, drawing: Drawing
    ) -> (parts: [PenPostItExpansion.Part], identity: PenPostItExpansion.Identity) {
        let chrome = drawing.chrome
        let style = chrome.style
        let label = chrome.label(weight: style.authorWeight)
        let top = box.height - textInsets.bottom - chrome.labelLine
        let left = textInsets.left
        let right = box.width - textInsets.right
        let diameter = style.identityDotDiameter * chrome.scale
        let color = drawing.identityColor(for: author)
        let ring = ink == style.inkOnDark
            ? PenPostItExpansion.Hairline(color: style.identityRingOnDark, width: style.identityRingWidth)
            : nil
        let dot = PenPostItExpansion.Part(
            role: .identityDot,
            frame: PenRect(x: left, y: top + (chrome.labelLine - diameter) / 2, width: diameter, height: diameter),
            paint: .shape(PenPostItExpansion.Shape(form: .ellipse, fill: color, hairline: ring))
        )
        let x = left + diameter + style.identityDotGap * chrome.scale
        let name = chrome.labelPart(
            .author, author, style: label, at: (x, top), maxWidth: max(0, right - x), color: ink.secondary,
            measure: drawing.measure
        )
        return ([dot, name], PenPostItExpansion.Identity(author: author, color: color))
    }

    /// The shadows a node's paper casts, as effects, for its painted extent: a note's or a
    /// prompt's ``Style/shadows``; none for a context or a comment.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - style: The look.
    /// - Returns: The effects, or `nil` for a node that is not a note, prompt or context.
    static func paperEffects(of node: PenNode, style: Style = .standard) -> [PenEffect]? {
        guard let variant = Variant(node.kind) else { return nil }
        if variant == .context || Metadata(node)?.type == .valid(.comment) { return [] }
        return style.shadows.map(\.effect)
    }

    /// The paper: the whole box, filled, edged inside and shadowed.
    static func plate(
        _ paper: PenHexColor, box: (width: Double, height: Double), cornerRadius: Double, hairline: PenHexColor,
        shadows: [PenPostItExpansion.Shadow], style: Style
    ) -> PenPostItExpansion.Part {
        PenPostItExpansion.Part(
            role: .plate,
            frame: PenRect(x: 0, y: 0, width: box.width, height: box.height),
            paint: .shape(PenPostItExpansion.Shape(
                form: .roundedRect(cornerRadius: cornerRadius), fill: paper,
                hairline: PenPostItExpansion.Hairline(color: hairline, width: style.hairlineWidth), shadows: shadows
            ))
        )
    }
}
