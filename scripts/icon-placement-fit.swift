#!/usr/bin/env swift

// Fits where Pen puts an icon's glyph in its box, from Pen's own PNG exports.
//
// Usage (from the repo root, sandbox disabled — the interpreter needs the toolchain):
//   xcrun swift scripts/icon-placement-fit.swift <fixture.pen> [<png dir>] [--scale 2]
//       [--opsz 24|auto] [--material-fonts <dir>]
//
// For every `icon` node on every top-level frame of <fixture.pen> it reads the frame's
// Pen export (`<fixture>-<frame name>.png` in <png dir>, default the fixture's directory,
// as `scripts/pen-oracle` names them), then searches for the glyph origin — pen x and
// baseline y, in points from the box's top-left — whose Core Text rasterisation best
// matches Pen's pixels in the box (least MAE over the box and a margin around it). It
// prints that fit beside what each candidate placement rule predicts:
//
//   ink      the glyph's outline bounds centred in the box (Woodcase's rule before VMKixs)
//   advance  the advance width centred across the box
//   line     the line box (hhea ascent + descent) centred down the box
//   pen      the same line box with ascent and descent each rounded to a whole point at
//            14 pt first: Pen's rule (PenIconFontRenderer.glyphOrigin)
//
// and the residual of each, so the rule that fits every library, size and box shape
// reads straight off the table. Reproduces the evidence in PenIconFonts.md
// ("Where the glyph sits"). Fonts come from Sources/Woodcase/IconFonts/Fonts and code
// points from the *Codepoints.swift tables beside them; Material Symbols is drawn at
// wght 200, Pen's default, unless the node sets `weight`, and at opsz 24, the font's default,
// which Pen never changes (`--opsz auto` lets Core Text set it from the point size, as it
// does unless told otherwise; `--material-fonts <dir>` draws with other Material Symbols
// TTFs of the same file names, e.g. the Google Fonts builds Pen downloads). macOS only (AppKit-free
// CoreGraphics/CoreText/ImageIO).

import CoreGraphics
import CoreText
import Foundation
import ImageIO

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
var scale: CGFloat = 2
if let i = args.firstIndex(of: "--scale"), i + 1 < args.count {
    scale = CGFloat(Double(args[i + 1]) ?? 2)
    args.removeSubrange(i ... i + 1)
}

/// Material Symbols' `opsz` axis: pinned to a value, or `nil` to let Core Text set it from
/// the point size (its automatic optical sizing, which Pen's engine does not do).
var opticalSize: Double? = 24
if let i = args.firstIndex(of: "--opsz"), i + 1 < args.count {
    opticalSize = args[i + 1] == "auto" ? nil : Double(args[i + 1])
    args.removeSubrange(i ... i + 1)
}

/// A directory of Material Symbols TTFs to draw with instead of the bundled ones.
var materialFontDir: URL?
if let i = args.firstIndex(of: "--material-fonts"), i + 1 < args.count {
    materialFontDir = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i ... i + 1)
}

guard let fixturePath = args.first else {
    fputs("usage: icon-placement-fit.swift <fixture.pen> [<png dir>] [--scale 2]\n", stderr)
    exit(2)
}

let fixtureURL = URL(fileURLWithPath: fixturePath)
let pngDir = args.count > 1 ? URL(fileURLWithPath: args[1]) : fixtureURL.deletingLastPathComponent()
let stem = fixtureURL.deletingPathExtension().lastPathComponent
let iconFonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Sources/Woodcase/IconFonts").standardizedFileURL

// MARK: - Fonts and code points

func codepoints(_ file: String) -> [String: UInt32] {
    let text = (try? String(contentsOf: iconFonts.appendingPathComponent(file), encoding: .utf8)) ?? ""
    var table: [String: UInt32] = [:]
    for match in text.matches(of: #/"([^"]+)": 0x([0-9A-Fa-f]+)/#) {
        table[String(match.1)] = UInt32(match.2, radix: 16)
    }
    return table
}

let tables: [String: [String: UInt32]] = [
    "lucide": codepoints("LucideCodepoints.swift"),
    "feather": codepoints("FeatherCodepoints.swift"),
    "phosphor": codepoints("PhosphorCodepoints.swift"),
    "material": codepoints("MaterialSymbolsCodepoints.swift"),
]

func fontFile(_ library: String) -> (file: String, table: String)? {
    switch library {
    case "lucide": ("lucide.ttf", "lucide")
    case "feather": ("feather.ttf", "feather")
    case "phosphor": ("Phosphor.ttf", "phosphor")
    case "Material Symbols Outlined": ("MaterialSymbolsOutlined.ttf", "material")
    case "Material Symbols Rounded": ("MaterialSymbolsRounded.ttf", "material")
    case "Material Symbols Sharp": ("MaterialSymbolsSharp.ttf", "material")
    default: nil
    }
}

func font(library: String, size: CGFloat, weight: Double?) -> CTFont? {
    guard let (file, _) = fontFile(library) else { return nil }
    let url = library.hasPrefix("Material Symbols") && materialFontDir != nil
        ? materialFontDir!.appendingPathComponent(file)
        : iconFonts.appendingPathComponent("Fonts/\(file)")
    // Registered from the file, as the renderer does, so the variation axis applies.
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String })
    else { return nil }
    let base = CTFontCreateWithName(name as CFString, size, nil)
    guard library.hasPrefix("Material Symbols") else { return base }
    var axes: [UInt32: Double] = [0x7767_6874: weight ?? 200] // 'wght'
    if let opticalSize { axes[0x6F70_737A] = opticalSize } // 'opsz'
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: axes] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
}

// MARK: - Pixels

struct Gray {
    var width: Int, height: Int, pixels: [UInt8]
    func at(_ x: Int, _ y: Int) -> UInt8 {
        x < 0 || y < 0 || x >= width || y >= height ? 255 : pixels[y * width + x]
    }
}

func load(_ url: URL) -> Gray? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return draw(width: image.width, height: image.height) { $0.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }
}

/// A white grayscale canvas, y down, with `body` drawn into it.
func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> Gray {
    var pixels = [UInt8](repeating: 255, count: width * height)
    pixels.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        body(context)
    }
    return Gray(width: width, height: height, pixels: pixels)
}

/// The darkness-weighted centroid of a window of `image`, relative to the window's origin.
func centroid(_ image: Gray, x: Int, y: Int, width: Int, height: Int) -> CGPoint {
    var mass = 0.0, sx = 0.0, sy = 0.0
    for j in 0 ..< height {
        for i in 0 ..< width {
            let ink = Double(255 - Int(image.at(x + i, y + j)))
            mass += ink
            sx += ink * Double(i)
            sy += ink * Double(j)
        }
    }
    return mass > 0 ? CGPoint(x: sx / mass, y: sy / mass) : .zero
}

// MARK: - Fit

struct Icon { var frame: String, name: String, library: String, icon: String, weight: Double?, box: CGRect }

let document = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
var icons: [Icon] = []
for case let frame as [String: Any] in document["children"] as? [Any] ?? [] {
    let frameName = frame["name"] as? String ?? ""
    for case let node as [String: Any] in frame["children"] as? [Any] ?? [] where node["type"] as? String == "icon" {
        func number(_ key: String) -> CGFloat {
            CGFloat((node[key] as? NSNumber)?.doubleValue ?? 0)
        }
        icons.append(Icon(
            frame: frameName, name: node["name"] as? String ?? "", library: node["library"] as? String ?? "",
            icon: node["icon"] as? String ?? "", weight: (node["weight"] as? NSNumber)?.doubleValue,
            box: CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height"))
        ))
    }
}

var exports: [String: Gray] = [:]
print("frame\ticon\tbox\tsize\tfit x\tfit base\tink dx\tink dy\tadv dx\tline dy\tpen dy\tasc\tdesc\tadv\tMAE")
for icon in icons {
    if exports[icon.frame] == nil {
        guard let image = load(pngDir.appendingPathComponent("\(stem)-\(icon.frame).png")) else {
            fputs("missing export for frame \(icon.frame)\n", stderr)
            exit(1)
        }
        exports[icon.frame] = image
    }
    let export = exports[icon.frame]!
    let size = min(icon.box.width, icon.box.height)
    guard let (_, tableName) = fontFile(icon.library),
          let point = tables[tableName]?[icon.icon], let scalar = Unicode.Scalar(point),
          let ctFont = font(library: icon.library, size: size * scale, weight: icon.weight)
    else {
        fputs("unknown icon \(icon.library)/\(icon.icon)\n", stderr)
        continue
    }
    let characters = Array(String(Character(scalar)).utf16)
    var glyph = CGGlyph(0)
    CTFontGetGlyphsForCharacters(ctFont, characters, &glyph, 1)
    guard let outline = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { continue }
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(ctFont, .horizontal, [glyph], &advance, 1)
    let bounds = outline.boundingBoxOfPath
    let ascent = CTFontGetAscent(ctFont), descent = CTFontGetDescent(ctFont)

    // The comparison window: the box plus a margin, in export pixels.
    let margin = 6 * scale
    let window = CGRect(
        x: icon.box.minX * scale - margin, y: icon.box.minY * scale - margin,
        width: icon.box.width * scale + 2 * margin, height: icon.box.height * scale + 2 * margin
    ).integral
    let wx = Int(window.minX), wy = Int(window.minY), ww = Int(window.width), wh = Int(window.height)

    /// The glyph drawn with its origin at (ox, by) px from the box's top-left, in the window, y down.
    func render(_ ox: CGFloat, _ by: CGFloat) -> Gray {
        // A bitmap context's first row is its top: drawing y up, the rows come out y down.
        draw(width: ww, height: wh) { context in
            context.setFillColor(gray: 0, alpha: 1)
            let x = icon.box.minX * scale - CGFloat(wx) + ox
            let baseline = icon.box.minY * scale - CGFloat(wy) + by
            context.translateBy(x: x, y: CGFloat(wh) - baseline)
            context.addPath(outline)
            context.fillPath()
        }
    }

    /// MAE of the glyph drawn with its origin at (ox, by) px from the box's top-left.
    func mae(_ ox: CGFloat, _ by: CGFloat) -> Double {
        let own = render(ox, by)
        var sum = 0
        for y in 0 ..< wh {
            for x in 0 ..< ww {
                sum += abs(Int(own.at(x, y)) - Int(export.at(wx + x, wy + y)))
            }
        }
        return Double(sum) / Double(ww * wh)
    }

    // Start where the ink's centroid lands on Pen's, then walk ever finer grids on MAE.
    let w = icon.box.width * scale, h = icon.box.height * scale
    let inkX = w / 2 - bounds.midX, inkY = h / 2 + bounds.midY
    let penCentroid = centroid(export, x: wx, y: wy, width: ww, height: wh)
    let ownCentroid = centroid(render(inkX, inkY), x: 0, y: 0, width: ww, height: wh)
    let startX = inkX + penCentroid.x - ownCentroid.x, startY = inkY + penCentroid.y - ownCentroid.y
    var best = (x: startX, y: startY, mae: mae(startX, startY))
    for step in [0.5, 0.125, 1.0 / 32] as [CGFloat] {
        let centre = best
        for i in -6 ... 6 {
            for j in -6 ... 6 {
                let x = centre.x + CGFloat(i) * step, y = centre.y + CGFloat(j) * step
                let m = mae(x, y)
                if m < best.mae { best = (x, y, m) }
            }
        }
    }
    let advX = (w - advance.width) / 2
    let lineY = (h - (ascent + descent)) / 2 + ascent
    let em = size * scale, reference: CGFloat = 14
    let penY = h / 2 + em * ((ascent * reference / em).rounded() - (descent * reference / em).rounded()) / (2 * reference)
    func pt(_ v: CGFloat) -> String {
        String(format: "%.2f", v / scale)
    }
    print([
        icon.frame, icon.name, "\(Int(icon.box.width))x\(Int(icon.box.height))", "\(Int(size))",
        pt(best.x), pt(best.y), pt(inkX - best.x), pt(inkY - best.y), pt(advX - best.x), pt(lineY - best.y), pt(penY - best.y),
        String(format: "%.3f", ascent / (size * scale)), String(format: "%.3f", descent / (size * scale)),
        String(format: "%.3f", advance.width / (size * scale)), String(format: "%.2f", best.mae),
    ].joined(separator: "\t"))
}
