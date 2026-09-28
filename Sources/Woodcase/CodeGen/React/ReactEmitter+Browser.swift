//
//  ReactEmitter+Browser.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    // MARK: - Browser Node Emission

    /// Emits an `<iframe>` of a `browser` node's page (ruling, Ben, 2026-09-26).
    ///
    /// `src` is ``PenNode/BrowserData/pageURL`` — the stored address with the
    /// `https://` Pen strips put back — and is left off when the node has no address,
    /// so the frame still holds the node's place. `title`, which assistive technology
    /// reads, is the node's name, then that address, then `browser`.
    ///
    /// The frame is sized and styled like a rectangle: width, height, corner radius,
    /// stroke and effects ride the style object, with `overflow: hidden` so the page is
    /// clipped to the radius and `border: none` to drop the browser's default inset
    /// border. `deviceId`, `zoom` and the scroll offsets are not emitted: the frame's
    /// size already is the viewport, and a cross-origin page's zoom and scroll position
    /// cannot be set from outside it.
    static func emitBrowser(
        _ node: PenNode,
        data: PenNode.BrowserData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)
        var styles: [(String, String)] = []

        let placement = ctx.placement(for: node.common)
        if let width = data.width, let cssWidth = emitSizing(width, placement: placement, fitsContent: false) {
            styles.append(("width", cssWidth))
        }
        if let height = data.height, let cssHeight = emitSizing(height, placement: placement, fitsContent: false) {
            styles.append(("height", cssHeight))
        }
        styles.append(("border", "\"none\""))
        styles.append(contentsOf: emitVisualStyles(
            fills: nil,
            box: .unknown,
            cornerRadius: data.cornerRadius,
            stroke: data,
            effects: data.effects,
            showsBackdrop: true,
            ctx: ctx
        ))
        styles.append(("overflow", "\"hidden\""))
        styles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        styles.append(contentsOf: emitCommonStyles(node.common, blendMode: nil, pivot: ctx.transformPivot(for: node.common)))
        styles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))
        substituteStateVars(&styles, pivot: ctx.transformPivot(for: node.common), ctx: ctx)

        let title = node.common.name ?? data.pageURL ?? PenNode.NodeType.browser.rawValue
        ctx.lines.append("\(pad)<iframe")
        if let source = data.pageURL {
            ctx.lines.append("\(pad)  src=\(jsxAttributeValue(source))")
        }
        ctx.lines.append("\(pad)  title=\(jsxAttributeValue(title))")
        ctx.lines.append("\(pad)  style={{")
        for (key, value) in styles {
            ctx.lines.append("\(pad)    \(key): \(value),")
        }
        ctx.lines.append("\(pad)  }}")
        ctx.lines.append("\(pad)/>")
    }

    /// A JSX attribute value holding `text` exactly.
    ///
    /// A JSX string attribute has no escapes, and a brace or an ampersand in one reads
    /// as something else, so text holding any of those — or a quote or a line break —
    /// is written as a JavaScript string expression instead: `{"…"}`.
    ///
    /// - Parameter text: The value.
    /// - Returns: `"text"` when that is safe, otherwise `{"escaped text"}`.
    static func jsxAttributeValue(_ text: String) -> String {
        let unsafe: Set<Character> = ["\"", "{", "}", "&", "<", ">", "\n", "\r", "\\"]
        guard text.contains(where: { unsafe.contains($0) }) else { return "\"\(text)\"" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let literal = (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        return "{\(literal)}"
    }
}
