// Measures every single-line IBM Plex Sans text in the layout-text-* fixtures in two
// candidate faces, beside the width Pen's own layout gave it — the evidence for which
// face Pen draws (leaf BpaSrF, project/2026-09-28-plex-variable-face.md).
//
// Usage (from the repo root):
//   swift scripts/plex-face-widths.swift <variable.ttf> [<static-dir>]
//
// <variable.ttf> is a variable IBM Plex Sans (wdth, wght): each text is set at its own
// weight on the `wght` axis. <static-dir>, when given, holds the static cuts
// IBMPlexSans-{Regular,Medium,SemiBold}.ttf (the suites' faces before BpaSrF; recover
// them with `git show 674f1ff:Tests/WoodcaseTests/Fonts/IBMPlexSans-Medium.ttf`), and each
// text is also set in the cut for its weight. Texts with a fixed or fill width, or that
// wrap, are skipped: only an auto-width text's box is its measured advance. Pen's layout
// rounds a text box's width up to a whole point, so a face matches when its width
// rounds up to Pen's.

import CoreText
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: plex-face-widths.swift <variable.ttf> [<static-dir>]\n".utf8))
    exit(64)
}

let variableURL = URL(fileURLWithPath: arguments[1])
let staticDirectory = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : nil
let fixtures = URL(fileURLWithPath: "Tests/WoodcaseTests/Fixtures")
let wghtTag = 0x7767_6874

/// The first face a font file holds.
func descriptor(_ url: URL) -> CTFontDescriptor {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let first = descriptors.first
    else { fatalError("no font in \(url.path)") }
    return first
}

/// The advance of `text` set in `font`, kerned as Core Text sets a line.
func width(_ text: String, _ font: CTFont, letterSpacing: Double) -> Double {
    var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font]
    if letterSpacing != 0 { attributes[.init(kCTKernAttributeName as String)] = letterSpacing }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

/// A CSS weight as a number.
func weight(_ value: Any?) -> Int {
    switch value as? String ?? "normal" {
    case "normal": 400
    case "bold": 700
    case let other: Int(other) ?? 400
    }
}

let variable = descriptor(variableURL)
let cuts = [400: "Regular", 500: "Medium", 600: "SemiBold"]

print("fixture\tid\tweight\tsize\ttext\tPen\tvariable\tstatic")
var variableHits = 0, staticHits = 0, total = 0
let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
    .filter { $0.hasPrefix("layout-text-") && $0.hasSuffix(".layout.json") }.sorted()
for name in names {
    let stem = String(name.dropLast(".layout.json".count))
    let layout = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(name))) as! [String: [String: Double]]
    let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("\(stem).pen"))) as! [String: Any]
    var texts: [[String: Any]] = []
    func walk(_ node: [String: Any]) {
        if node["type"] as? String == "text", node["width"] == nil, node["textGrowth"] == nil { texts.append(node) }
        for child in node["children"] as? [[String: Any]] ?? [] {
            walk(child)
        }
    }
    for child in document["children"] as? [[String: Any]] ?? [] {
        walk(child)
    }
    for text in texts {
        guard let id = text["id"] as? String, let content = text["content"] as? String,
              let penWidth = layout[id]?["width"] else { continue }
        let size = text["fontSize"] as? Double ?? 14
        let w = weight(text["fontWeight"])
        let spacing = text["letterSpacing"] as? Double ?? 0
        let instance = CTFontDescriptorCreateCopyWithVariation(variable, wghtTag as CFNumber, CGFloat(w))
        let variableWidth = width(content, CTFontCreateWithFontDescriptor(instance, size, nil), letterSpacing: spacing)
        var staticWidth = Double.nan
        if let staticDirectory, let cut = cuts[w] {
            let font = CTFontCreateWithFontDescriptor(descriptor(staticDirectory.appendingPathComponent("IBMPlexSans-\(cut).ttf")), size, nil)
            staticWidth = width(content, font, letterSpacing: spacing)
        }
        total += 1
        if variableWidth.rounded(.up) == penWidth { variableHits += 1 }
        if staticWidth.rounded(.up) == penWidth { staticHits += 1 }
        print("\(stem)\t\(id)\t\(w)\t\(size)\t\(content)\t\(penWidth)\t\(String(format: "%.3f", variableWidth))\t\(String(format: "%.3f", staticWidth))")
    }
}

print("rounded-up width equals Pen's: variable \(variableHits)/\(total), static \(staticHits)/\(total)")
