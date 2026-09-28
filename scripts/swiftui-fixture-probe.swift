#!/usr/bin/env swift
//
// swiftui-fixture-probe — render hand-written SwiftUI for four Pen fixtures with ImageRenderer and
// print each one's MAE against Pen's own PNG export.
//
// The views are written the way a SwiftUI emitter would write them; variants show what a choice
// costs (the default gradient interpolation against `.colorSpace(.device)`, Inter's automatic
// optical sizing against pinned-off). MAE is PenSnapshotTestHelpers.meanAbsoluteError's
// arithmetic (PixelPeeper's `maeSteps`, 0–255): sRGB, premultiplied RGBA8, both images drawn scaled
// onto the smaller width and height, the mean over every channel. A standalone script cannot import
// PixelPeeper, so the loop is repeated here.
//
// Usage (sandbox disabled — the Swift toolchain):
//   xcrun swift scripts/swiftui-fixture-probe.swift [--out <dir>]
//
// It runs in the interpreter, which is also the fastest single-view loop measured (about 1 s
// warm). Inter comes from the font cache, ~/.woodcase/fonts/inter (render any Inter document
// with `woodcase` once to fill it). `--out` also writes each render as a PNG.
// Reproduces the table in project/2026-09-26-swiftui-codegen-feasibility.md §4. macOS 26+.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Harness

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let premul = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

func registerFonts(_ dir: String) {
    let fm = FileManager.default
    guard let e = fm.enumerator(atPath: dir) else { return }
    for case let p as String in e where p.hasSuffix(".ttf") || p.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: dir + "/" + p) as CFURL, .process, nil)
    }
}

func pixels(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb, bitmapInfo: premul)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return px
}

/// Same arithmetic as PenSnapshotTestHelpers.meanAbsoluteError: sRGB premultiplied RGBA8, both images drawn
/// scaled onto the smaller size (a resample, not a crop), mean over all channels.
func mae(_ a: CGImage, _ b: CGImage) -> (Double, Int) {
    let w = min(a.width, b.width), h = min(a.height, b.height)
    let pa = pixels(a, w, h), pb = pixels(b, w, h)
    var s = 0, mx = 0
    for i in 0 ..< pa.count {
        let d = abs(Int(pa[i]) - Int(pb[i])); s += d; mx = max(mx, d)
    }
    return (Double(s) / Double(pa.count), mx)
}

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func savePNG(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}

@MainActor func renderPNG(_ view: some View, scale: Double, to path: String) -> CGImage {
    let r = ImageRenderer(content: view)
    r.scale = scale
    let img = r.cgImage!
    savePNG(img, path)
    return img
}

@MainActor func report(_ name: String, _ view: some View, scale: Double, ref: String?, out: String) {
    let img = renderPNG(view, scale: scale, to: "\(out)/\(name.filter { $0.isLetter || $0.isNumber }).png")
    var line = "\(name): \(img.width)x\(img.height) px"
    if let ref, let r = load(ref) {
        let (m, mx) = mae(img, r)
        line += " ref=\(r.width)x\(r.height) MAE=\(String(format: "%.3f", m)) max=\(mx)"
    }
    print(line)
}

// MARK: - Views

/// render-text.pen, 1x reference.
struct RenderText: View {
    var lineHeightExact = true
    /// The reference was exported after Pen dropped rich text: those two rows are blank in it.
    var hideRich = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hello World")
                .font(.custom("Inter", size: 14))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Bold Title")
                .font(.custom("Inter", size: 24).weight(.bold))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Centered Text")
                .font(.custom("Inter", size: 16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Vertically Centered")
                .font(.custom("Inter", size: 16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
            Text("Bold and Italic")
                .font(.custom("Inter", size: 16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .opacity(hideRich ? 0 : 1)
            Text("Underline Strikethrough")
                .font(.custom("Inter", size: 16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .opacity(hideRich ? 0 : 1)
            Text("This is a longer piece of text that should wrap within the fixed width container to test line wrapping behavior.")
                .font(.custom("Inter", size: 14))
                .foregroundStyle(Color(.sRGB, red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("LETTER SPACING")
                .font(.custom("Inter", size: 14))
                .tracking(4)
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Line one\nLine two\nLine three")
                .font(.custom("Inter", size: 14))
                .lineHeight(lineHeightExact ? .exact(points: 28) : .multiple(factor: 2))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(32)
        .frame(width: 500)
        .background(Color(.sRGB, red: 1, green: 1, blue: 1))
    }
}

/// render-gradients.pen, first artboard, 2x reference.
struct RenderGradients: View {
    let red = Color(.sRGB, red: 1, green: 0, blue: 0)
    let blue = Color(.sRGB, red: 0, green: 0, blue: 1)
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Rectangle()
                .fill(LinearGradient(stops: [.init(color: red, location: 0), .init(color: blue, location: 1)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(LinearGradient(stops: [.init(color: red, location: 0), .init(color: blue, location: 1)],
                                     startPoint: .trailing, endPoint: .leading))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(LinearGradient(stops: [.init(color: red, location: 0),
                                             .init(color: Color(.sRGB, red: 1, green: 1, blue: 0), location: 0.5),
                                             .init(color: blue, location: 1)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(EllipticalGradient(stops: [.init(color: Color(.sRGB, red: 1, green: 1, blue: 1), location: 0),
                                                 .init(color: Color(.sRGB, red: 0, green: 0, blue: 0), location: 1)],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(AngularGradient(stops: [.init(color: red, location: 0),
                                              .init(color: Color(.sRGB, red: 0, green: 1, blue: 0), location: 0.33),
                                              .init(color: blue, location: 0.66),
                                              .init(color: red, location: 1)],
                                      center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                .frame(width: 120, height: 120)
            Ellipse()
                .fill(LinearGradient(stops: [.init(color: Color(.sRGB, red: 1, green: 0x88 / 255, blue: 0), location: 0),
                                             .init(color: Color(.sRGB, red: 0x88 / 255, green: 0, blue: 1), location: 1)],
                                     startPoint: UnitPoint(x: 0.5 + 0.5 * sin(.pi / 4), y: 0.5 + 0.5 * cos(.pi / 4)),
                                     endPoint: UnitPoint(x: 0.5 - 0.5 * sin(.pi / 4), y: 0.5 - 0.5 * cos(.pi / 4))))
                .frame(width: 120, height: 120)
        }
        .padding(32)
        .background(Color(.sRGB, red: 1, green: 1, blue: 1))
    }
}

/// layout-justify-space-between.pen, 1x reference: the idiomatic Spacer form.
struct SpaceBetweenSpacers: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0)).frame(width: 60, height: 60)
            Spacer(minLength: 0)
            Rectangle().fill(Color(.sRGB, red: 0, green: 1, blue: 0)).frame(width: 60, height: 60)
            Spacer(minLength: 0)
            Rectangle().fill(Color(.sRGB, red: 0, green: 0, blue: 1)).frame(width: 60, height: 60)
        }
        .frame(width: 400, height: 100, alignment: .topLeading)
        .background(Color(.sRGB, red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255))
    }
}

/// The support-library form: one Layout that implements Pen's main-axis distribution.
struct PenFlex: Layout {
    enum Justify { case start, center, end, spaceBetween, spaceAround }
    var horizontal = true
    var gap: CGFloat = 0
    var justify = Justify.start

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let main = sizes.reduce(0) { $0 + (horizontal ? $1.width : $1.height) } + gap * CGFloat(max(sizes.count - 1, 0))
        let cross = sizes.map { horizontal ? $0.height : $0.width }.max() ?? 0
        let w = proposal.width ?? (horizontal ? main : cross)
        let h = proposal.height ?? (horizontal ? cross : main)
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let n = CGFloat(sizes.count)
        let used = sizes.reduce(0) { $0 + (horizontal ? $1.width : $1.height) }
        let avail = (horizontal ? bounds.width : bounds.height) - used
        var pos: CGFloat, step: CGFloat
        switch justify {
        case .start: pos = 0; step = gap
        case .center: pos = (avail - gap * (n - 1)) / 2; step = gap
        case .end: pos = avail - gap * (n - 1); step = gap
        case .spaceBetween: pos = 0; step = n > 1 ? max(avail / (n - 1), gap) : 0
        case .spaceAround: step = max(avail / n, gap); pos = step / 2
        }
        for (i, s) in subviews.enumerated() {
            let p = horizontal ? CGPoint(x: bounds.minX + pos, y: bounds.minY) : CGPoint(x: bounds.minX, y: bounds.minY + pos)
            s.place(at: p, anchor: .topLeading, proposal: ProposedViewSize(sizes[i]))
            pos += (horizontal ? sizes[i].width : sizes[i].height) + step
        }
    }
}

struct SpaceBetweenLayout: View {
    var body: some View {
        PenFlex(horizontal: true, gap: 0, justify: .spaceBetween) {
            Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0)).frame(width: 60, height: 60)
            Rectangle().fill(Color(.sRGB, red: 0, green: 1, blue: 0)).frame(width: 60, height: 60)
            Rectangle().fill(Color(.sRGB, red: 0, green: 0, blue: 1)).frame(width: 60, height: 60)
        }
        .frame(width: 400, height: 100)
        .background(Color(.sRGB, red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255))
    }
}

/// layout-nested.pen, 1x reference.
struct LayoutNested: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0)).frame(width: 80, height: 50)
                Rectangle().fill(Color(.sRGB, red: 0, green: 1, blue: 0)).frame(width: 80, height: 50)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.sRGB, red: 0xE0 / 255, green: 0xE0 / 255, blue: 0xE0 / 255))
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color(.sRGB, red: 0, green: 0, blue: 1)).frame(width: 60, height: 40)
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 1)).frame(width: 100, height: 40)
                Rectangle().fill(Color(.sRGB, red: 0, green: 1, blue: 1)).frame(width: 40, height: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.sRGB, red: 0xD0 / 255, green: 0xD0 / 255, blue: 0xD0 / 255))
        }
        .frame(width: 400, height: 300, alignment: .topLeading)
        .background(Color(.sRGB, red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255))
    }
}

/// render-gradients.pen, first artboard, 2x reference.
struct RenderGradientsDevice: View {
    let red = Color(.sRGB, red: 1, green: 0, blue: 0)
    let blue = Color(.sRGB, red: 0, green: 0, blue: 1)
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Rectangle()
                .fill(.linearGradient(Gradient(stops: [.init(color: red, location: 0), .init(color: blue, location: 1)]).colorSpace(.device),
                                      startPoint: .bottom, endPoint: .top))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(.linearGradient(Gradient(stops: [.init(color: red, location: 0), .init(color: blue, location: 1)]).colorSpace(.device),
                                      startPoint: .trailing, endPoint: .leading))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(.linearGradient(Gradient(stops: [.init(color: red, location: 0),
                                                       .init(color: Color(.sRGB, red: 1, green: 1, blue: 0), location: 0.5),
                                                       .init(color: blue, location: 1)]).colorSpace(.device),
                                      startPoint: .bottom, endPoint: .top))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(.ellipticalGradient(Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 1, blue: 1), location: 0),
                                                           .init(color: Color(.sRGB, red: 0, green: 0, blue: 0), location: 1)]).colorSpace(.device),
                                          center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: 120, height: 120)
            Rectangle()
                .fill(.angularGradient(Gradient(stops: [.init(color: red, location: 0),
                                                        .init(color: Color(.sRGB, red: 0, green: 1, blue: 0), location: 0.33),
                                                        .init(color: blue, location: 0.66),
                                                        .init(color: red, location: 1)]).colorSpace(.device),
                                       center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                .frame(width: 120, height: 120)
            Ellipse()
                .fill(.linearGradient(Gradient(stops: [.init(color: Color(.sRGB, red: 1, green: 0x88 / 255, blue: 0), location: 0),
                                                       .init(color: Color(.sRGB, red: 0x88 / 255, green: 0, blue: 1), location: 1)]).colorSpace(.device),
                                      startPoint: UnitPoint(x: 0.5 + 0.5 * sin(.pi / 4), y: 0.5 + 0.5 * cos(.pi / 4)),
                                      endPoint: UnitPoint(x: 0.5 - 0.5 * sin(.pi / 4), y: 0.5 - 0.5 * cos(.pi / 4))))
                .frame(width: 120, height: 120)
        }
        .padding(32)
        .background(Color(.sRGB, red: 1, green: 1, blue: 1))
    }
}

/// Inter with optical sizing pinned off, the way a browser-less Skia draws a variable font.
func interNoOpsz(_ size: CGFloat, bold: Bool = false) -> Font {
    var attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: "Inter", kCTFontOpticalSizeAttribute: "none"]
    if bold { attrs[kCTFontVariationAttribute] = [0x7767_6874: 700] } // 'wght'
    let d = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    return Font(CTFontCreateWithFontDescriptor(d, size, nil))
}

/// render-text.pen, 1x reference.
struct RenderTextNoOpsz: View {
    var lineHeightExact = true
    /// The reference was exported after Pen dropped rich text: those two rows are blank in it.
    var hideRich = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hello World")
                .font(interNoOpsz(14))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Bold Title")
                .font(interNoOpsz(24, bold: true))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Centered Text")
                .font(interNoOpsz(16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Vertically Centered")
                .font(interNoOpsz(16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
            Text("Bold and Italic")
                .font(interNoOpsz(16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .opacity(hideRich ? 0 : 1)
            Text("Underline Strikethrough")
                .font(interNoOpsz(16))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .opacity(hideRich ? 0 : 1)
            Text("This is a longer piece of text that should wrap within the fixed width container to test line wrapping behavior.")
                .font(interNoOpsz(14))
                .foregroundStyle(Color(.sRGB, red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("LETTER SPACING")
                .font(interNoOpsz(14))
                .tracking(4)
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
            Text("Line one\nLine two\nLine three")
                .font(interNoOpsz(14))
                .lineHeight(lineHeightExact ? .exact(points: 28) : .multiple(factor: 2))
                .foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 0))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(32)
        .frame(width: 500)
        .background(Color(.sRGB, red: 1, green: 1, blue: 1))
    }
}

// MARK: - Main

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/WoodcaseTests/Fixtures").path
let args = CommandLine.arguments
let outDir = args.firstIndex(of: "--out").map { args[$0 + 1] } ?? NSTemporaryDirectory() + "swiftui-fixture-probe"
MainActor.assumeIsolated {
    let fonts = NSHomeDirectory() + "/.woodcase/fonts/inter"
    if !FileManager.default.fileExists(atPath: fonts) { print("note: no Inter at \(fonts); text rows will use a fallback font") }
    registerFonts(fonts)
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let text = fixtures + "/render-text.png", grad = fixtures + "/render-gradients.png"
    report("render-text (Font.custom, automatic optical size)", RenderText(), scale: 1, ref: text, out: outDir)
    report("render-text (optical size pinned off)", RenderTextNoOpsz(), scale: 1, ref: text, out: outDir)
    report("render-text (pinned off, rich rows hidden as in the ref)", RenderTextNoOpsz(hideRich: true), scale: 1, ref: text, out: outDir)
    report("render-gradients (default interpolation)", RenderGradients(), scale: 2, ref: grad, out: outDir)
    report("render-gradients (.colorSpace(.device))", RenderGradientsDevice(), scale: 2, ref: grad, out: outDir)
    report("space-between (HStack + Spacer)", SpaceBetweenSpacers(), scale: 1, ref: fixtures + "/layout-justify-space-between.png", out: outDir)
    report("space-between (PenFlex Layout)", SpaceBetweenLayout(), scale: 1, ref: fixtures + "/layout-justify-space-between.png", out: outDir)
    report("layout-nested (VStack/HStack)", LayoutNested(), scale: 1, ref: fixtures + "/layout-nested.png", out: outDir)
}
