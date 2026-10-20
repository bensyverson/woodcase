#!/usr/bin/env swift

// Sweeps Core Graphics blend modes against W3C Compositing and Blending Level 1 and prints
// each mode's largest 8-bit error (premultiplied) over random 8-bit colors at alpha 0.4 and 1,
// with the worst case when it exceeds 1.6 steps. It is the evidence behind
// `PenBlendMode.compositing` (which modes the reference renderer composites per pixel).
//
// Usage:
//   scripts/cg-blend-sweep.swift            # translucent and opaque colors
//   scripts/cg-blend-sweep.swift opaque     # both colors opaque
//
// linearBurn is measured as CG's plusDarker and linearDodge as plusLighter. macOS only.

import CoreGraphics
import Foundation

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func cg(_ mode: CGBlendMode, src: [Double], dst: [Double]) -> [Double] {
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    ctx.setFillColor(CGColor(colorSpace: cs, components: dst.map { CGFloat($0) })!)
    ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    ctx.setBlendMode(mode)
    ctx.setFillColor(CGColor(colorSpace: cs, components: src.map { CGFloat($0) })!)
    ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (0 ..< 4).map { Double(p[$0]) }
}

func D(_ cb: Double) -> Double {
    cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : cb.squareRoot()
}

func sep(_ m: String, _ cb: Double, _ s: Double) -> Double {
    switch m {
    case "darken": min(cb, s)
    case "multiply": cb * s
    case "linearBurn": max(0, cb + s - 1)
    case "colorBurn": cb == 1 ? 1 : s == 0 ? 0 : 1 - min(1, (1 - cb) / s)
    case "lighten": max(cb, s)
    case "screen": cb + s - cb * s
    case "linearDodge": min(1, cb + s)
    case "colorDodge": cb == 0 ? 0 : s == 1 ? 1 : min(1, cb / (1 - s))
    case "hardLight": s <= 0.5 ? cb * 2 * s : sep("screen", cb, 2 * s - 1)
    case "overlay": sep("hardLight", s, cb)
    case "softLight": s <= 0.5 ? cb - (1 - 2 * s) * cb * (1 - cb) : cb + (2 * s - 1) * (D(cb) - cb)
    case "difference": abs(cb - s)
    case "exclusion": cb + s - 2 * cb * s
    default: s
    }
}

func lum(_ c: [Double]) -> Double {
    0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
}

func clip(_ c: [Double]) -> [Double] {
    let l = lum(c), n = c.min()!, x = c.max()!
    var r = c
    if n < 0 { r = r.map { l + ($0 - l) * l / (l - n) } }
    if x > 1 { r = r.map { l + ($0 - l) * (1 - l) / (x - l) } }
    return r
}

func setLum(_ c: [Double], _ l: Double) -> [Double] {
    let d = l - lum(c); return clip(c.map { $0 + d })
}

func sat(_ c: [Double]) -> Double {
    c.max()! - c.min()!
}

func setSat(_ c: [Double], _ s: Double) -> [Double] {
    let mx = c.max()!, mn = c.min()!
    return c.map { mx > mn ? ($0 - mn) * s / (mx - mn) : 0 }
}

func blend(_ m: String, _ cb: [Double], _ s: [Double]) -> [Double] {
    switch m {
    case "hue": setLum(setSat(s, sat(cb)), lum(cb))
    case "saturation": setLum(setSat(cb, sat(s)), lum(cb))
    case "color": setLum(s, lum(cb))
    case "luminosity": setLum(cb, lum(s))
    default: (0 ..< 3).map { sep(m, cb[$0], s[$0]) }
    }
}

func w3c(_ m: String, src: [Double], dst: [Double]) -> [Double] {
    let sa = src[3], ba = dst[3]
    let b = blend(m, Array(dst[0 ..< 3]), Array(src[0 ..< 3]))
    var out = (0 ..< 3).map { i -> Double in
        let csp = (1 - ba) * src[i] + ba * b[i]
        return (sa * csp + ba * dst[i] * (1 - sa)) * 255
    }
    out.append((sa + ba * (1 - sa)) * 255)
    return out
}

let modes: [(String, CGBlendMode)] = [("darken", .darken), ("multiply", .multiply), ("linearBurn", .plusDarker), ("colorBurn", .colorBurn), ("lighten", .lighten), ("screen", .screen), ("linearDodge", .plusLighter), ("colorDodge", .colorDodge), ("overlay", .overlay), ("softLight", .softLight), ("hardLight", .hardLight), ("difference", .difference), ("exclusion", .exclusion), ("hue", .hue), ("saturation", .saturation), ("color", .color), ("luminosity", .luminosity)]

var rng = SystemRandomNumberGenerator()
let levels: [Double] = [0, 26, 51, 77, 128, 179, 230, 255].map { $0 / 255 }
let alphas: [Double] = [102.0 / 255, 1]
let filter = CommandLine.arguments.dropFirst().first // "opaque" restricts both alphas to 1
for (name, mode) in modes {
    var worst = 0.0
    var worstCase = ""
    for _ in 0 ..< 1500 {
        let sa = filter == "opaque" ? 1 : alphas.randomElement(using: &rng)!
        let ba = filter == "opaque" ? 1 : alphas.randomElement(using: &rng)!
        let src = (0 ..< 3).map { _ in levels.randomElement(using: &rng)! } + [sa]
        let dst = (0 ..< 3).map { _ in levels.randomElement(using: &rng)! } + [ba]
        let a = cg(mode, src: src, dst: dst)
        let b = w3c(name, src: src, dst: dst)
        let err = zip(a, b).map { abs($0 - $1) }.max()!
        if err > worst { worst = err; worstCase = "src \(src) dst \(dst) cg \(a) w3c \(b.map { ($0 * 10).rounded() / 10 })" }
    }
    print(name, String(format: "%.1f", worst), worst > 1.6 ? worstCase : "")
}
