//
//  ReactEmitter+TextLayout.swift
//  Woodcase
//

import CoreText
import Foundation

extension ReactEmitter {
    // MARK: - Text Layout

    /// The declarations that set a text's lines the way Pen sets them: its line height,
    /// the default optical size, how it wraps, and where its lines sit in a taller box.
    ///
    /// - An explicit `lineHeight` stays a multiple of the font size. With none, Pen sets
    ///   each line at the font's natural pitch (``naturalLinePitch(_:theme:)``), written in px;
    ///   where the emitter cannot know the font the browser will use, `normal`.
    /// - `font-optical-sizing: none`: Pen draws a variable font at its default optical size
    ///   whatever the point size, where a browser picks the cut for the size (Inter above
    ///   14 pt is narrower). Every text writes it, so no stylesheet a project could leave
    ///   out is needed.
    /// - `white-space`: Pen keeps a text's newlines and spaces, and wraps only a text whose
    ///   width is set — a fixed-width growth, or a width that is not `fit_content` — as
    ///   `PenLayoutEngine` measures it; an auto-width text is one line per newline (`pre`),
    ///   any other wraps too (`pre-wrap`).
    /// - `textAlignVertical`: `middle` and `bottom` make the element a column that centres
    ///   or sinks its lines; `top` is the normal flow.
    /// - A top-aligned text whose font is known here is moved so its first baseline lands
    ///   where Pen puts it (``baselineCorrection(_:theme:)``).
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - theme: The document's theme manifest, which resolves a variable font.
    /// - Returns: The declarations, in the order they are written.
    static func textLayoutStyles(_ data: PenNode.TextData, theme: ThemeManifest) -> [(String, String)] {
        var styles: [(String, String)] = []
        if let lineHeight = data.lineHeight {
            styles.append(("lineHeight", emitPenValue(lineHeight)))
        } else if let pitch = naturalLinePitch(data, theme: theme) {
            styles.append(("lineHeight", "\"\(cssNumber(pitch))px\""))
        } else {
            styles.append(("lineHeight", "\"normal\""))
        }
        styles.append(("fontOpticalSizing", "\"none\""))
        styles.append(("whiteSpace", textWraps(data) ? "\"pre-wrap\"" : "\"pre\""))
        if let justify = verticalJustification(data.textAlignVertical) {
            styles.append(("display", "\"flex\""))
            styles.append(("flexDirection", "\"column\""))
            styles.append(("justifyContent", "\"\(justify)\""))
        } else if let shift = baselineCorrection(data, theme: theme) {
            styles.append(("marginTop", cssNumber(shift)))
            styles.append(("marginBottom", cssNumber(-shift)))
        }
        return styles
    }

    /// How far a top-aligned text must move down, in points, for its first baseline to land
    /// on the whole point Pen puts it on, or `nil` when the font is not known here or the
    /// baselines already agree.
    ///
    /// CSS puts the first baseline at `ascent + (line-height − ascent − descent) / 2`, the
    /// line height being the emitted one — the natural pitch in px, or the multiple of the
    /// size — and a browser snaps it to a device pixel; Pen puts it on a whole point
    /// (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``). IBM Plex Sans at 13 pt is
    /// 13.375 in CSS and 13 in Pen: 27 px at 2x against 26. The move is a margin pair
    /// (`marginTop` and its negation below), which leaves the margin box, and so the text's
    /// place in a flex or block flow, unchanged. Middle and bottom alignment keep the
    /// browser's baseline: where Pen rounds theirs is not measured.
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - theme: The document's theme manifest, which resolves a variable family or size.
    /// - Returns: The move in points, or `nil`.
    static func baselineCorrection(_ data: PenNode.TextData, theme: ThemeManifest) -> Double? {
        guard let (font, size) = textFont(data, theme: theme) else { return nil }
        let lineHeight = data.lineHeight?.literalValue
        if data.lineHeight != nil, lineHeight == nil { return nil }
        let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: size, font: font)
        let cssLineHeight = lineHeight.map { size * $0 } ?? Double(pitch)
        let ascent = Double(CTFontGetAscent(font))
        let cssBaseline = ascent + (cssLineHeight - ascent - Double(CTFontGetDescent(font))) / 2
        let shift = Double(PenTextMeasurer.firstBaseline(of: font, lineHeight: lineHeight, pitch: pitch)) - cssBaseline
        return abs(shift) < 0.0005 ? nil : shift
    }

    /// The pitch Pen sets a text's lines at when it has no `lineHeight`, in points
    /// (``PenTextMeasurer/naturalLineHeight(of:)``: the font's ascent, descent and leading,
    /// rounded to a whole point), or `nil` when the page's font cannot be known here.
    ///
    /// It is measured on the font this machine resolves, so it is known only for a family
    /// Core Text has, named as a literal or by a variable that holds that one family under
    /// every theme — the family the emitted page asks for; the size likewise. A text with
    /// no family draws in whatever the page inherits, a variable whose value changes with
    /// the theme would need a pitch per theme, and a family this machine lacks would be
    /// measured in the fallback's metrics; each of those is `nil`.
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - theme: The document's theme manifest, which resolves a variable family or size.
    /// - Returns: The pitch in points, or `nil`.
    static func naturalLinePitch(_ data: PenNode.TextData, theme: ThemeManifest) -> Double? {
        guard let (font, _) = textFont(data, theme: theme) else { return nil }
        return Double(PenTextMeasurer.naturalLineHeight(of: font))
    }

    /// The font the page draws a text in, as this machine resolves it, and its size, or
    /// `nil` when either cannot be known here (``naturalLinePitch(_:theme:)`` says when).
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - theme: The document's theme manifest, which resolves a variable family or size.
    /// - Returns: The font and its size in points, or `nil`.
    private static func textFont(_ data: PenNode.TextData, theme: ThemeManifest) -> (CTFont, Double)? {
        let family: String? = switch data.fontFamily {
        case let .literal(name)?: name
        case let .variable(name)?: if case let .string(value)? = themeConstant(name, in: theme) { value } else { nil }
        case nil: nil
        }
        guard let family, PenTextMeasurer.fontFamilyAvailable(family) else { return nil }
        let size: Double? = switch data.fontSize {
        case nil: PenTextMeasurer.defaultFontSize
        case let .literal(value)?: value
        case let .variable(name)?: switch themeConstant(name, in: theme) {
            case let .int(value)?: Double(value)
            case let .double(value)?: value
            default: nil
            }
        }
        guard let size else { return nil }
        let font = PenTextMeasurer.resolveFont(
            family: family,
            size: size,
            weight: data.fontWeight?.literalValue ?? "normal",
            style: data.fontStyle?.literalValue ?? "normal"
        )
        return (font, size)
    }

    /// The value of variable `name` when it is the same under every theme, else `nil`.
    private static func themeConstant(_ name: String, in theme: ThemeManifest) -> AnyCodable? {
        guard let values = theme.variables.first(where: { $0.name == name })?.values.map(\.value),
              let first = values.first, values.allSatisfy({ $0 == first })
        else { return nil }
        return first
    }

    /// Whether Pen wraps a text's lines at its width: a fixed-width growth, or a width
    /// that is set rather than `fit_content` (`PenLayoutEngine.layoutLeafNode`).
    private static func textWraps(_ data: PenNode.TextData) -> Bool {
        switch data.textGrowth {
        case .fixedWidth?, .fixedWidthHeight?: true
        case .auto?, nil: !(data.width ?? .fitContent(fallback: nil)).isFitContent
        }
    }

    /// The column's `justify-content` for a vertical alignment, or `nil` for the top.
    private static func verticalJustification(_ alignment: PenTextAlignVertical?) -> String? {
        switch alignment {
        case .middle?: "center"
        case .bottom?: "flex-end"
        case .top?, nil: nil
        }
    }

    /// A text's content as a JSX child that reaches the page exactly.
    ///
    /// JSX collapses a line break in its text and reads braces and angle brackets as
    /// syntax, so content holding any of those is written as a string expression,
    /// `{"Line one\nLine two"}`; anything else stays bare text.
    ///
    /// - Parameter text: The content.
    /// - Returns: The JSX child.
    static func jsxTextChild(_ text: String) -> String {
        let unsafe: Set<Character> = ["{", "}", "<", ">", "\n", "\r", "&"]
        guard text.contains(where: { unsafe.contains($0) }) else { return text }
        return jsxAttributeValue(text)
    }
}
