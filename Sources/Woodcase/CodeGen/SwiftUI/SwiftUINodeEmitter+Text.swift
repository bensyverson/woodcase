//
//  SwiftUINodeEmitter+Text.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A text node: `Text` in the support file's `penFont` (which pins optical sizing off
    /// and carries the line height), a frame for its growth mode, and its paint — one plain
    /// color as `foregroundStyle`, anything else as layers seen through its glyphs
    /// (`penTextFill`). A text with no enabled fill is `.foregroundStyle(.clear)`: Pen
    /// draws it as nothing, in either color scheme. A text with inner shadows always takes
    /// the layers, which draw the shadows inside its glyphs over its paint.
    ///
    /// `auto` text sizes to its content and never wraps, so it is `.fixedSize()`: left
    /// flexible, a `Text` offered less than its ideal width wraps, where Pen lets it
    /// overflow. `fixed-width` wraps inside its width and grows down; `fixed-width-height`
    /// is framed on both axes, placed by `textAlignVertical`.
    func text(_ node: PenNode, data: PenNode.TextData, in container: Container) -> SwiftUIViewCode {
        var unemitted = unemittedStrokes(data.stroke)
        // In a component's body, a text prop is the copy: `Text(label)`, verbatim.
        let head = scope.prop(.text, at: node.id).map { "Text(\($0.name))" } ?? textHead(data.content, unemitted: &unemitted)
        var view = SwiftUIViewCode(head: head)

        if let spacing = data.letterSpacing.flatMap({ number($0, unemitted: &unemitted) }), !spacing.isZero {
            view = view.modified(".tracking(\(spacing.code))")
        }
        if data.underline?.literalValue == true {
            view = view.modified(".underline()")
        }
        if data.strikethrough?.literalValue == true {
            view = view.modified(".strikethrough()")
        }
        view = view.modified(fontModifier(data, unemitted: &unemitted))

        let align = data.textAlign ?? .left
        if align == .justify {
            unemitted.append("justified alignment (SwiftUI's Text has none; drawn leading)")
        }
        let horizontal: SwiftUIAlignment.Horizontal = switch align {
        case .left, .justify: .leading
        case .center: .center
        case .right: .trailing
        }
        if horizontal != .leading {
            view = view.modified(".multilineTextAlignment(.\(horizontal == .center ? "center" : "trailing"))")
        }
        // Where a plain color's `foregroundStyle` goes: before the growth frame.
        let styleIndex = view.modifiers.count
        let growth = data.textGrowth ?? .auto
        var width = Dimension.fit
        var height = Dimension.fit
        if growth == .auto {
            view = view.modified(".fixedSize()")
        } else {
            width = dimension(declaredSizing(node, axis: .width), in: container)
            var vertical = SwiftUIAlignment.Vertical.center
            if growth == .fixedWidth {
                view = view.modified(".fixedSize(horizontal: false, vertical: true)")
            } else {
                height = dimension(declaredSizing(node, axis: .height), in: container)
                vertical = switch data.textAlignVertical ?? .top {
                case .top: .top
                case .middle: .center
                case .bottom: .bottom
                }
            }
            view.modifiers += frameModifiers(
                width: width, height: height,
                alignment: SwiftUIAlignment(horizontal: horizontal, vertical: vertical)
            )
        }
        let layers = paintLayers(data.fills, box: fillBox(width: width, height: height), of: node.id, unemitted: &unemitted)
        let innerShadows = effects(data.effects).inner
        if !innerShadows.isEmpty {
            // The glyphs cast an inner shadow unpainted, so even one color is a layer here,
            // and a text with no paint still shows its shadow over nothing.
            let paint = layers.isEmpty ? [SwiftUIViewCode(head: "Color.clear")] : layers.map(\.view)
            view.modifiers.append(SwiftUIViewCode.Modifier(
                ".penTextFill(innerShadows: \(Effects.Shadow.styles(innerShadows)))", content: paint
            ))
        } else if layers.count == 1, layers[0].isColor, layers[0].blendMode == nil, let color = layers[0].style {
            view.modifiers.insert(SwiftUIViewCode.Modifier(".foregroundStyle(\(color))"), at: styleIndex)
        } else if !layers.isEmpty {
            // After the frame: Pen lays a text's paint out over the node's box.
            view.modifiers.append(SwiftUIViewCode.Modifier(".penTextFill", content: layers.map(\.view)))
        } else if !(data.fills?.all ?? []).contains(where: \.isEnabled) {
            // Pen draws a text with no enabled paint as nothing; left unstyled, SwiftUI
            // would draw it in `.primary`, black or white by the color scheme.
            view.modifiers.insert(SwiftUIViewCode.Modifier(".foregroundStyle(.clear)"), at: styleIndex)
        }
        warnUnemitted(node, unemitted)
        return view
    }

    /// `.penFont(…)`, writing only what differs from its defaults: weight 400, upright,
    /// the font's natural line height as Pen rounds it.
    private func fontModifier(_ data: PenNode.TextData, unemitted: inout [String]) -> String {
        var arguments: [String] = []
        if let family = data.fontFamily.flatMap({ string($0, unemitted: &unemitted) }) {
            arguments.append(family)
        }
        let size = data.fontSize.flatMap { number($0, unemitted: &unemitted) } ?? SwiftUINumber(PenTextMeasurer.defaultFontSize)
        arguments.append("size: \(size.code)")
        if let weight = data.fontWeight?.literalValue {
            let css = PenFontWeight.cssWeight(weight)
            if css != 400 { arguments.append("weight: \(SwiftUILiteral.number(css))") }
        }
        if data.fontStyle?.literalValue?.lowercased() == "italic" {
            arguments.append("italic: true")
        }
        if let multiple = data.lineHeight.flatMap({ number($0, unemitted: &unemitted) }), multiple.smallest > 0 {
            arguments.append("lineHeight: \(multiple.code)")
        }
        return ".penFont(\(arguments.joined(separator: ", ")))"
    }

    /// The `Text` of a node's content: a string variable read through the theme
    /// (`Text(theme.greeting)`), or the copy as a literal. A `$name` no variable of the
    /// document has is the literal it almost certainly was (`$186`, a price), as the
    /// resolver reads it; one of another type is reported and drawn as that literal too.
    private func textHead(_ content: PenValue<String>?, unemitted: inout [String]) -> String {
        switch content {
        case let .variable(name)?:
            guard scope.theme?.tokens[name] != nil, let read = string(.variable(name), unemitted: &unemitted) else {
                return Self.textHead("$" + name)
            }
            return "Text(\(read))"
        case let .literal(text)?:
            return Self.textHead(text)
        case nil:
            return Self.textHead("")
        }
    }

    /// `Text("…")`, or `Text(verbatim: "…")` when the copy holds characters a
    /// `LocalizedStringKey` would read as Markdown, or something its Markdown would link
    /// and tint — an email address, a URL.
    static func textHead(_ content: String) -> String {
        let markdown: Set<Character> = ["*", "_", "`", "[", "]", "~", "@"]
        let literal = SwiftUILiteral.string(content)
        let linkable = content.contains("://") || content.contains("www.")
        return linkable || content.contains(where: markdown.contains) ? "Text(verbatim: \(literal))" : "Text(\(literal))"
    }
}
