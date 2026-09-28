// Times the ways Core Text can measure a text for layout, back to back, over the texts of
// a .pen document — the micro-benchmark behind "Text measurement typesets once" in
// WoodcasePerformance.md.
//
// Usage (from the repo root; compile with -O, the interpreter is not what ships):
//   swiftc -O scripts/text-measure-bench.swift -o "$TMPDIR/text-measure-bench"
//   "$TMPDIR/text-measure-bench" [document.pen] [reps]
//
// Defaults: Tests/WoodcaseTests/Fixtures/woodcase-app.pen, 40 reps. Registers the
// committed Inter; every text is set in Inter at its own font size and line height (or
// Pen's natural pitch), wrapped at its own fixed width if it has one. Each rep times the
// whole corpus once per strategy, alternating, so machine load hits every strategy alike;
// the minimum over the reps is printed. Before timing, it checks that every strategy
// answers the same size as the old two-pass measurement (except "suggested size only",
// whose height is Core Text's frame height, not Pen's) and prints the mismatch counts.
//
// Strategies:
//   two passes       CTFramesetterSuggestFrameSizeWithConstraints + a CTFrame for the
//                    line count (PenTextMeasurer before leaf cHuvso)
//   one frame        the width and line count from one CTFrame
//   typesetter       CTTypesetterSuggestLineBreak + CTTypesetterCreateLine (what ships)
//   suggested only   CTFramesetterSuggestFrameSizeWithConstraints alone (the cost before
//                    natural line height, commit e578829)

import CoreText
import Foundation

let arguments = CommandLine.arguments
let documentPath = arguments.count > 1 ? arguments[1] : "Tests/WoodcaseTests/Fixtures/woodcase-app.pen"
let reps = arguments.count > 2 ? Int(arguments[2]) ?? 40 : 40
let interURL = URL(fileURLWithPath: "Tests/WoodcaseTests/Fonts/Inter[opsz,wght].ttf")
guard CTFontManagerRegisterFontsForURL(interURL as CFURL, .process, nil) else {
    fatalError("Could not register \(interURL.path); run from the repo root.")
}

/// One text to measure: the styled string, its wrapping width and its line pitch.
struct Case {
    let string: CFAttributedString
    let width: CGFloat?
    let pitch: CGFloat
}

func paragraphStyle(_ pitch: CGFloat) -> CTParagraphStyle {
    var height = pitch
    return withUnsafeMutablePointer(to: &height) { pointer in
        var settings = [
            CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: pointer),
            CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: pointer),
        ]
        return CTParagraphStyleCreate(&settings, settings.count)
    }
}

func collectTexts(_ value: Any, into cases: inout [Case]) {
    if let object = value as? [String: Any] {
        if object["type"] as? String == "text", let text = object["content"] as? String, !text.isEmpty {
            let size = CGFloat((object["fontSize"] as? NSNumber)?.doubleValue ?? 14)
            let font = CTFontCreateWithName("Inter" as CFString, size, nil)
            let lineHeight = (object["lineHeight"] as? NSNumber).map { CGFloat($0.doubleValue) }
            let natural = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded()
            let pitch = lineHeight.map { ($0 * size).rounded() } ?? natural
            let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTParagraphStyleAttributeName: paragraphStyle(pitch)]
            let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
            let width = (object["width"] as? NSNumber).map { CGFloat($0.doubleValue) }
            cases.append(Case(string: string, width: width, pitch: pitch))
        }
        for child in object.values {
            collectTexts(child, into: &cases)
        }
    } else if let array = value as? [Any] {
        for child in array {
            collectTexts(child, into: &cases)
        }
    }
}

let document = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: documentPath)))
var cases: [Case] = []
collectTexts(document, into: &cases)

let unbounded: CGFloat = 1e7

func suggested(_ framesetter: CTFramesetter, _ width: CGFloat?) -> CGSize {
    let constraints = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    return CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraints, nil)
}

func frameLines(_ framesetter: CTFramesetter, _ width: CGFloat?) -> [CTLine] {
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width ?? unbounded, height: unbounded), transform: nil)
    return CTFrameGetLines(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)) as! [CTLine]
}

func widest(_ lines: [CTLine]) -> CGFloat {
    lines.reduce(CGFloat(0)) { max($0, CGFloat(CTLineGetTypographicBounds($1, nil, nil, nil)) - CTLineGetTrailingWhitespaceWidth($1)) }
}

func twoPasses(_ item: Case) -> CGSize {
    let framesetter = CTFramesetterCreateWithAttributedString(item.string)
    let fit = suggested(framesetter, item.width)
    let count = frameLines(framesetter, item.width).count
    return CGSize(width: ceil(fit.width), height: ceil(CGFloat(count) * item.pitch))
}

func oneFrame(_ item: Case) -> CGSize {
    let lines = frameLines(CTFramesetterCreateWithAttributedString(item.string), item.width)
    return CGSize(width: ceil(widest(lines)), height: ceil(CGFloat(lines.count) * item.pitch))
}

func typesetter(_ item: Case) -> CGSize {
    let typesetter = CTTypesetterCreateWithAttributedString(item.string)
    let length = CFAttributedStringGetLength(item.string)
    var lines: [CTLine] = []
    var start = 0
    while start < length {
        let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(item.width ?? unbounded))
        lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
        start += count
    }
    return CGSize(width: ceil(widest(lines)), height: ceil(CGFloat(lines.count) * item.pitch))
}

func suggestedOnly(_ item: Case) -> CGSize {
    let fit = suggested(CTFramesetterCreateWithAttributedString(item.string), item.width)
    return CGSize(width: ceil(fit.width), height: ceil(fit.height))
}

let strategies: [(name: String, measure: (Case) -> CGSize)] = [
    ("two passes", twoPasses), ("one frame", oneFrame), ("typesetter", typesetter), ("suggested only", suggestedOnly),
]

for strategy in strategies.dropFirst() {
    let mismatches = cases.count(where: { strategy.measure($0) != twoPasses($0) })
    print("\(strategy.name): \(mismatches) of \(cases.count) sizes differ from two passes")
}

let clock = ContinuousClock()
var best = [Duration](repeating: .seconds(1_000_000), count: strategies.count)
for _ in 0 ..< reps {
    for (index, strategy) in strategies.enumerated() {
        let elapsed = clock.measure {
            for item in cases {
                _ = strategy.measure(item)
            }
        }
        best[index] = min(best[index], elapsed)
    }
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

print("\(cases.count) texts from \(documentPath), minimum of \(reps) alternating reps:")
for (index, strategy) in strategies.enumerated() {
    print(String(format: "  %-15@ %.3f ms", strategy.name as NSString, milliseconds(best[index])))
}
