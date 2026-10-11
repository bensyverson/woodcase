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
    /// name at the bottom; resolved, it fades. A prompt is a white card with its model chip,
    /// ▶ Run and its run's status; a context is a quiet card with an ⓘ mark. No note carries
    /// a kind mark. See <doc:PenPostItLook>.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - width: Its laid-out width.
    ///   - height: Its laid-out height, grown to fit its text.
    ///   - style: The look.
    ///   - measure: The text measurer the chrome's labels are measured with; the layout's.
    /// - Returns: The expansion, or `nil` for a node that is not a note, prompt or context,
    ///   and for a comment message (`woodcase.type: comment`), which Penumbra draws.
    static func expansion(
        of node: PenNode,
        width: Double,
        height: Double,
        style: Style = .standard,
        measure: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> PenPostItExpansion? {
        guard let variant = Variant(node.kind), let text = node.noteTextStyle else { return nil }
        let metadata = Metadata(node)
        if metadata?.type == .valid(.comment) { return nil }
        let chrome = Chrome(style: style, fontSize: text.fontSize)
        let box = (width: width, height: height)
        return switch variant {
        case .note: noteExpansion(node, metadata: metadata, box: box, chrome: chrome, measure: measure)
        case .prompt: promptExpansion(node, metadata: metadata, box: box, chrome: chrome, measure: measure)
        case .context: contextExpansion(node, box: box, chrome: chrome, measure: measure)
        }
    }
}

extension PenPostIt {
    /// A post-it: its paper, its body, and its author line.
    static func noteExpansion(
        _ node: PenNode, metadata: Metadata?, box: (width: Double, height: Double), chrome: Chrome,
        measure: TextMeasurer
    ) -> PenPostItExpansion {
        let style = chrome.style
        let footer = Chrome.Footer(metadata)
        let isResolved = footer?.isResolved ?? false
        let tint = metadata?.tint?.value ?? Tint.default.color
        let paper = isResolved ? tint.mixed(toward: style.resolvedPaper, by: style.resolvedMix) : tint
        let ink = Ink(on: paper, style: style)
        var parts = [plate(
            paper, box: box, cornerRadius: style.noteCornerRadius, hairline: style.hairline,
            shadows: isResolved ? Array(style.shadows.prefix(1)) : style.shadows, style: style
        )]
        let body = bodyPart(of: node, box: box, color: isResolved ? ink.secondary : ink.primary, ink: ink, style: style)
        if let part = body.part { parts.append(part) }
        var identity: PenPostItExpansion.Identity?
        if let footer {
            let footerParts = footerParts(footer, box: box, ink: ink, chrome: chrome, measure: measure)
            parts += footerParts.parts
            identity = footerParts.identity
        }
        return PenPostItExpansion(
            variant: .note, width: box.width, height: box.height, ink: ink,
            parts: parts, mentions: body.mentions, identity: identity
        )
    }

    /// The author's dot and name at the bottom left, and "Resolved" at the bottom right.
    private static func footerParts(
        _ footer: Chrome.Footer, box: (width: Double, height: Double), ink: Ink, chrome: Chrome,
        measure: TextMeasurer
    ) -> (parts: [PenPostItExpansion.Part], identity: PenPostItExpansion.Identity?) {
        let style = chrome.style
        let label = chrome.label(weight: style.authorWeight)
        let top = box.height - textInsets.bottom - chrome.labelLine
        let left = textInsets.left
        var right = box.width - textInsets.right
        var parts: [PenPostItExpansion.Part] = []
        if footer.isResolved {
            let width = chrome.width(of: style.resolvedLabel, style: label, measure: measure)
            let x = max(left, right - width)
            parts.append(chrome.labelPart(
                .resolvedLabel, style.resolvedLabel, style: label, at: (x, top),
                maxWidth: right - x, color: ink.secondary, measure: measure
            ))
            right = x - style.identityDotGap * chrome.scale
        }
        guard let author = footer.author else { return (parts, nil) }
        let diameter = style.identityDotDiameter * chrome.scale
        let color = identityColor(for: author, style: style)
        let dot = PenPostItExpansion.Part(
            role: .identityDot,
            frame: PenRect(x: left, y: top + (chrome.labelLine - diameter) / 2, width: diameter, height: diameter),
            paint: .shape(PenPostItExpansion.Shape(form: .ellipse, fill: color))
        )
        let x = left + diameter + style.identityDotGap * chrome.scale
        let name = chrome.labelPart(
            .author, author, style: label, at: (x, top), maxWidth: max(0, right - x), color: ink.secondary, measure: measure
        )
        return ([dot, name] + parts, PenPostItExpansion.Identity(author: author, color: color))
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
