//
//  PenPostIt+CardExpansion.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// A prompt: a white card with its header and model chip, its body, and a run row of
    /// the run's status and ▶ Run — or, while the prompt is queued, Cancel, which takes it
    /// off the queue (Penumbra's interaction spec §10.6). The button is measured from its
    /// word either way, so a caller hit-testing ``PenPostItExpansion/Role/runButton`` finds
    /// it where it is drawn.
    static func promptExpansion(
        _ node: PenNode, metadata: Metadata?, box: (width: Double, height: Double), drawing: Drawing
    ) -> PenPostItExpansion {
        let chrome = drawing.chrome
        let measure = drawing.measure
        let style = chrome.style
        let ink = Ink(on: style.promptPaper, style: style)
        let left = textInsets.left
        let right = box.width - textInsets.right
        let top = textInsets.top
        var parts = [plate(
            style.promptPaper, box: box, cornerRadius: style.cardCornerRadius, hairline: style.hairline,
            shadows: style.shadows, style: style
        )]

        // The header, and the model chip at the right.
        let headerStyle = chrome.label(weight: style.headerWeight, tracking: style.headerTracking)
        let headerY = top + (chrome.chipHeight - chrome.labelLine) / 2
        let header = chrome.labelPart(
            .header, drawing.text(.promptTitle), style: headerStyle, at: (left, headerY),
            maxWidth: max(0, right - left), color: ink.secondary, label: .promptTitle, measure: measure
        )
        parts.append(header)
        if case let .prompt(data) = node.kind, let model = data.model, !model.isEmpty {
            let padX = style.chipPaddingX * chrome.scale
            let chipStyle = chrome.label(weight: style.chipWeight)
            let room = right - (left + header.frame.width + style.infoMarkGap * chrome.scale) - 2 * padX
            let (text, width) = chrome.fitted(model, style: chipStyle, maxWidth: max(0, room), measure: measure)
            let chip = PenRect(x: right - width - 2 * padX, y: top, width: width + 2 * padX, height: chrome.chipHeight)
            parts.append(PenPostItExpansion.Part(
                role: .modelChip, frame: chip,
                paint: .shape(PenPostItExpansion.Shape(form: .roundedRect(cornerRadius: chip.height / 2), fill: style.chipFill))
            ))
            parts.append(chrome.labelPart(
                .modelLabel, text, style: chipStyle, at: (chip.x + padX, top + style.chipPaddingY * chrome.scale),
                maxWidth: width, color: ink.secondary, measure: measure
            ))
        }

        let content = body(of: node, box: box, color: ink.primary, ink: ink, paper: style.promptPaper, drawing: drawing)
        parts += content.parts

        // The run row: ▶ Run, or Cancel while queued, at the right; the status at the left.
        let rowTop = box.height - textInsets.bottom - chrome.runRow
        let runStyle = chrome.label(size: chrome.runSize, weight: style.runWeight)
        let padX = style.runPaddingX * chrome.scale
        let buttonLabel: Label = metadata?.runState?.value == .queued ? .cancel : .run
        let runLabel = drawing.text(buttonLabel)
        let labelWidth = chrome.width(of: runLabel, style: runStyle, measure: measure)
        let button = PenRect(x: right - labelWidth - 2 * padX, y: rowTop, width: labelWidth + 2 * padX, height: chrome.runRow)
        parts.append(PenPostItExpansion.Part(
            role: .runButton, frame: button,
            paint: .shape(PenPostItExpansion.Shape(
                form: .roundedRect(cornerRadius: style.runCornerRadius * chrome.scale), fill: style.runButtonFill
            ))
        ))
        parts.append(chrome.labelPart(
            .runLabel, runLabel, style: runStyle, at: (button.x + padX, rowTop + style.runPaddingY * chrome.scale),
            maxWidth: labelWidth, color: style.runButtonInk, label: buttonLabel, measure: measure
        ))
        if let state = metadata?.runState?.value {
            let diameter = style.statusDotDiameter * chrome.scale
            parts.append(PenPostItExpansion.Part(
                role: .statusDot,
                frame: PenRect(x: left, y: rowTop + (chrome.runRow - diameter) / 2, width: diameter, height: diameter),
                paint: .shape(PenPostItExpansion.Shape(form: .ellipse, fill: style.statusColor(state)))
            ))
            let label = Label.status(state, requestedBy: metadata?.requestedBy)
            let x = left + diameter + style.statusDotGap * chrome.scale
            parts.append(chrome.labelPart(
                .status, drawing.text(label), style: chrome.label(weight: PenTextStyle.defaultFontWeight),
                at: (x, rowTop + (chrome.runRow - chrome.labelLine) / 2),
                maxWidth: max(0, button.x - style.footerGap * chrome.scale - x), color: ink.secondary, label: label,
                measure: measure
            ))
        }
        return PenPostItExpansion(
            variant: .prompt, width: box.width, height: box.height, ink: ink, parts: parts, mentions: content.mentions,
            checkboxes: content.checkboxes
        )
    }

    /// A context: a quiet card with an ⓘ mark and its header, then its body.
    static func contextExpansion(
        _ node: PenNode, box: (width: Double, height: Double), drawing: Drawing
    ) -> PenPostItExpansion {
        let chrome = drawing.chrome
        let measure = drawing.measure
        let style = chrome.style
        let ink = Ink(on: style.contextPaper, style: style)
        let left = textInsets.left
        let top = textInsets.top
        var parts = [plate(
            style.contextPaper, box: box, cornerRadius: style.cardCornerRadius, hairline: style.contextHairline,
            shadows: [], style: style
        )]
        let diameter = style.infoMarkDiameter * chrome.scale
        let mark = PenRect(x: left, y: top + (chrome.contextHeader - diameter) / 2, width: diameter, height: diameter)
        parts.append(PenPostItExpansion.Part(
            role: .infoMark, frame: mark,
            paint: .shape(PenPostItExpansion.Shape(
                form: .ellipse, fill: nil,
                hairline: PenPostItExpansion.Hairline(color: style.infoMarkColor, width: style.infoMarkStroke * chrome.scale)
            ))
        ))
        let glyphStyle = chrome.label(size: style.infoGlyphFontSize * chrome.scale, weight: style.infoGlyphWeight)
        let glyphWidth = chrome.width(of: style.infoGlyph, style: glyphStyle, measure: measure)
        let glyphLine = chrome.lineHeight(of: glyphStyle)
        parts.append(chrome.labelPart(
            .infoGlyph, style.infoGlyph, style: glyphStyle,
            at: (mark.x + (diameter - glyphWidth) / 2, mark.y + (diameter - glyphLine) / 2),
            maxWidth: diameter, color: style.infoMarkColor, measure: measure
        ))
        let x = left + diameter + style.infoMarkGap * chrome.scale
        parts.append(chrome.labelPart(
            .header, drawing.text(.contextTitle),
            style: chrome.label(weight: style.headerWeight, tracking: style.headerTracking),
            at: (x, top + (chrome.contextHeader - chrome.labelLine) / 2),
            maxWidth: max(0, box.width - textInsets.right - x), color: ink.secondary, label: .contextTitle,
            measure: measure
        ))
        let content = body(of: node, box: box, color: ink.primary, ink: ink, paper: style.contextPaper, drawing: drawing)
        parts += content.parts
        return PenPostItExpansion(
            variant: .context, width: box.width, height: box.height, ink: ink, parts: parts, mentions: content.mentions,
            checkboxes: content.checkboxes
        )
    }
}
