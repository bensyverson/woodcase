//
//  FigmaImportSession+Text.swift
//  Woodcase
//

extension FigmaImportSession {
    /// A text node, read from `textData` and the node's own style; the glyph outlines in
    /// `derivedTextData` are Figma's rendering of it and play no part, so a color emoji,
    /// whose glyph blob is empty, keeps its character.
    mutating func text(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        let characters = record["textData"]?["characters"]?.stringValue ?? ""
        let fontSize = record["fontSize"]?.doubleValue ?? 12
        let font = FigmaFontName(record["fontName"])
        let face = font.face(in: record["derivedTextData"])
        var data = PenNode.TextData(
            content: .literal(characters),
            fontFamily: .literal(font.family), fontSize: .literal(fontSize),
            fontWeight: .literal(String(Int(face.weight))), fontStyle: .literal(face.isItalic ? "italic" : "normal"),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        )
        data.lineHeight = lineHeight(of: record, fontSize: fontSize, face: face).map { .literal($0) }
        if let spacing = record["letterSpacing"], let value = spacing["value"]?.doubleValue, value != 0 {
            data.letterSpacing = .literal(spacing["units"]?.enumName == "PERCENT" ? value / 100 * fontSize : value)
        }
        switch record["textAutoResize"]?.enumName {
        case "WIDTH_AND_HEIGHT":
            data.textGrowth = .auto
        case "HEIGHT":
            data.textGrowth = .fixedWidth
            data.width = .fixed(size.width)
        default:
            data.textGrowth = .fixedWidthHeight
            data.width = .fixed(size.width)
            data.height = .fixed(size.height)
        }
        data.textAlign = switch record["textAlignHorizontal"]?.enumName {
        case "CENTER": .center
        case "RIGHT": .right
        case "JUSTIFIED": .justify
        default: nil
        }
        data.textAlignVertical = switch record["textAlignVertical"]?.enumName {
        case "CENTER": .middle
        case "BOTTOM": .bottom
        default: nil
        }
        switch record["textDecoration"]?.enumName {
        case "UNDERLINE": data.underline = .literal(true)
        case "STRIKETHROUGH": data.strikethrough = .literal(true)
        default: break
        }
        reportTextFeatures(of: record)
        let runs = styledRuns(of: record, base: (font, face, fontSize))
        if !runs.isEmpty {
            var metadata = common.metadata ?? PenMetadata(type: nil)
            metadata.textSpans = PenTextSpans(text: characters, runs: runs)
            common.metadata = metadata
        }
        return .text(data)
    }

    /// The line height as Pen's multiple of the font size, or `nil` for the font's own.
    ///
    /// Figma's UI percentage ("150%", a multiple of the size) is stored as `RAW`: the
    /// fixture plugin set T1c to `{ value: 120, unit: 'PERCENT' }` and the message holds
    /// `{ value: 1.2, units: RAW }`. Its "Auto" is stored as 100 `PERCENT`, which T1a pins as
    /// the font's natural height, not the size: at 32 pt its baselines are 39 pt apart
    /// (Inter's 1.2102 × 32), not 32. So a stored percentage is read as a percentage of the
    /// natural height (`derivedTextData.fontMetaData`); no capture holds one other than 100.
    /// Pixels are a pitch.
    private func lineHeight(of record: KiwiRecord, fontSize: Double, face: FigmaFontName.Face) -> Double? {
        guard let lineHeight = record["lineHeight"], let value = lineHeight["value"]?.doubleValue, fontSize > 0 else { return nil }
        switch lineHeight["units"]?.enumName {
        case "PIXELS": return value / fontSize
        case "RAW": return value
        default: return value == 100 ? nil : value / 100 * (face.naturalLineHeight ?? 1)
        }
    }

    /// Reports the text features Pen has no property for.
    private mutating func reportTextFeatures(of record: KiwiRecord) {
        if let truncation = record["textTruncation"]?.enumName, truncation != "DISABLED" {
            report(.textTruncation, .dropped, on: record)
        }
        let lines = record["textData"]?["lines"]?.arrayValue ?? []
        if lines.contains(where: { ($0["lineType"]?.enumName ?? "PLAIN") != "PLAIN" }) {
            report(.textList, .dropped, on: record)
        }
        if let textCase = record["textCase"]?.enumName, textCase != "ORIGINAL" {
            report(.textCase, .dropped, on: record, detail: textCase)
        }
        for key in ["paragraphSpacing", "paragraphIndent"] where (record[key]?.doubleValue ?? 0) != 0 {
            report(.paragraph, .dropped, on: record, detail: key)
        }
        if record["hyperlink"] != nil {
            report(.hyperlink, .dropped, on: record)
        }
    }

    /// Each stretch of characters whose style override differs from the node's, as a run
    /// holding only what differs.
    ///
    /// `textData.characterStyleIDs` names a `styleOverrideTable` entry per UTF-16 code unit,
    /// 0 for the node's own style; characters past its end take the node's style.
    private mutating func styledRuns(
        of record: KiwiRecord, base: (font: FigmaFontName, face: FigmaFontName.Face, size: Double)
    ) -> [PenTextRun] {
        let textData = record["textData"]
        let ids = (textData?["characterStyleIDs"]?.arrayValue ?? []).compactMap(\.uintValue)
        var overrides: [UInt32: KiwiValue] = [:]
        for entry in textData?["styleOverrideTable"]?.arrayValue ?? [] {
            if let id = entry["styleID"]?.uintValue { overrides[id] = entry }
        }
        var runs: [PenTextRun] = []
        var start = 0
        while start < ids.count {
            var end = start
            while end < ids.count, ids[end] == ids[start] {
                end += 1
            }
            if ids[start] != 0, let entry = overrides[ids[start]], let run = run(entry, start: start, end: end, base: base, on: record) {
                runs.append(run)
            }
            start = end
        }
        return runs
    }

    /// One style override as a run over `start..<end`, or `nil` when nothing in it differs.
    private mutating func run(
        _ entry: KiwiValue, start: Int, end: Int, base: (font: FigmaFontName, face: FigmaFontName.Face, size: Double),
        on record: KiwiRecord
    ) -> PenTextRun? {
        var run = PenTextRun(start: start, end: end)
        if entry["fontName"] != nil {
            let font = FigmaFontName(entry["fontName"])
            let face = font.face(in: record["derivedTextData"])
            if font.family != base.font.family { run.fontFamily = font.family }
            if face.weight != base.face.weight { run.fontWeight = face.weight }
            if face.isItalic != base.face.isItalic { run.isItalic = face.isItalic }
        }
        if let size = entry["fontSize"]?.doubleValue, size != base.size { run.fontSize = size }
        if let paint = entry["fillPaints"]?.arrayValue?.first(where: { $0["type"]?.enumName == "SOLID" }),
           let color = FigmaColor(paint["color"])
        {
            run.fill = color.penHexColor(opacity: paint["opacity"]?.doubleValue ?? 1)
        }
        switch entry["textDecoration"]?.enumName {
        case "UNDERLINE": run.underline = true
        case "STRIKETHROUGH": run.strikethrough = true
        default: break
        }
        let read: Set = ["styleID", "fontName", "fontSize", "fillPaints", "textDecoration", "fontVersion", "fontVariations"]
        for field in entry.recordValue?.fields.keys.sorted() ?? [] where !read.contains(field) {
            report(.unreadField, .dropped, on: record, detail: "styleOverrideTable.\(field)")
        }
        return run == PenTextRun(start: start, end: end) ? nil : run
    }
}
