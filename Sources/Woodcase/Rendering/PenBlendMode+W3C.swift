//
//  PenBlendMode+W3C.swift
//  Woodcase
//

/// The blend modes' formulas as W3C Compositing and Blending Level 1 defines them
/// (https://www.w3.org/TR/compositing-1/), for the reference renderer's per-pixel path.
///
/// Every color is in the `0…1` range of the context's own encoding, which is how W3C
/// blends (sRGB-encoded, not linear). Linear burn and linear dodge are not in Level 1;
/// they take Photoshop's formulas, `max(0, Cb + Cs − 1)` and `min(1, Cb + Cs)`, through
/// the same general formula — Ben's ruling of 2026-10-20 (Penumbra
/// `project/2026-10-14-feature-enhancements-plan.md` §5 item 9).
public extension PenBlendMode {
    /// `B(Cb, Cs)`: the blended color of a straight (un-premultiplied) `source` over a
    /// straight `backdrop`, before either alpha is applied.
    ///
    /// `unknown` blends as `normal`, which is the source itself.
    func blend(backdrop cb: SIMD3<Double>, source cs: SIMD3<Double>) -> SIMD3<Double> {
        switch self {
        case .hue:
            Self.setLum(Self.setSat(cs, Self.sat(cb)), Self.lum(cb))
        case .saturation:
            Self.setLum(Self.setSat(cb, Self.sat(cs)), Self.lum(cb))
        case .color:
            Self.setLum(cs, Self.lum(cb))
        case .luminosity:
            Self.setLum(cb, Self.lum(cs))
        default:
            SIMD3(
                blendChannel(backdrop: cb.x, source: cs.x),
                blendChannel(backdrop: cb.y, source: cs.y),
                blendChannel(backdrop: cb.z, source: cs.z)
            )
        }
    }

    /// Composites a premultiplied `source` over a premultiplied `backdrop` by this mode:
    /// W3C's source-over with blending, `co = αs·(1 − αb)·Cs + αs·αb·B(Cb, Cs) + (1 − αs)·αb·Cb`
    /// and `αo = αs + αb·(1 − αs)`. The result is premultiplied; each vector is
    /// `(r, g, b, a)`.
    ///
    /// Over a transparent backdrop the source shows unchanged; under a transparent source
    /// the backdrop does.
    func composite(source: SIMD4<Double>, over backdrop: SIMD4<Double>) -> SIMD4<Double> {
        let alphaS = source.w
        let alphaB = backdrop.w
        guard alphaS > 0 else { return backdrop }
        let rgbS = SIMD3(source.x, source.y, source.z)
        let rgbB = SIMD3(backdrop.x, backdrop.y, backdrop.z)
        let cs = rgbS / alphaS
        let cb = alphaB > 0 ? rgbB / alphaB : SIMD3<Double>(repeating: 0)
        let blended = blend(backdrop: cb, source: cs)
        let color = alphaS * (1 - alphaB) * cs + alphaS * alphaB * blended + (1 - alphaS) * rgbB
        return SIMD4(color.x, color.y, color.z, alphaS + alphaB * (1 - alphaS))
    }

    // MARK: - Separable modes

    /// One channel of a separable mode's `B(Cb, Cs)`.
    private func blendChannel(backdrop cb: Double, source cs: Double) -> Double {
        switch self {
        case .normal, .unknown, .hue, .saturation, .color, .luminosity:
            cs
        case .darken:
            min(cb, cs)
        case .multiply:
            cb * cs
        case .linearBurn:
            max(0, cb + cs - 1)
        case .colorBurn:
            cb >= 1 ? 1 : cs <= 0 ? 0 : 1 - min(1, (1 - cb) / cs)
        case .light:
            max(cb, cs)
        case .screen:
            cb + cs - cb * cs
        case .linearDodge:
            min(1, cb + cs)
        case .colorDodge:
            cb <= 0 ? 0 : cs >= 1 ? 1 : min(1, cb / (1 - cs))
        case .overlay:
            Self.hardLight(backdrop: cs, source: cb)
        case .softLight:
            Self.softLight(backdrop: cb, source: cs)
        case .hardLight:
            Self.hardLight(backdrop: cb, source: cs)
        case .difference:
            abs(cb - cs)
        case .exclusion:
            cb + cs - 2 * cb * cs
        }
    }

    /// W3C's hard light; overlay is hard light with its operands swapped.
    private static func hardLight(backdrop cb: Double, source cs: Double) -> Double {
        cs <= 0.5 ? cb * 2 * cs : cb + (2 * cs - 1) - cb * (2 * cs - 1)
    }

    /// W3C's soft light — not Photoshop's, which differs where the backdrop is at or below
    /// 0.25 and the source above 0.5, nor Core Graphics' own.
    private static func softLight(backdrop cb: Double, source cs: Double) -> Double {
        if cs <= 0.5 {
            return cb - (1 - 2 * cs) * cb * (1 - cb)
        }
        let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : cb.squareRoot()
        return cb + (2 * cs - 1) * (d - cb)
    }

    // MARK: - Non-separable modes

    /// W3C's `Lum(C)`.
    private static func lum(_ c: SIMD3<Double>) -> Double {
        0.3 * c.x + 0.59 * c.y + 0.11 * c.z
    }

    /// W3C's `ClipColor(C)`: pulls an out-of-range color back along its luminosity.
    private static func clipColor(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = lum(c)
        let n = c.min()
        let x = c.max()
        var clipped = c
        if n < 0 {
            clipped = l + (clipped - l) * l / (l - n)
        }
        if x > 1 {
            clipped = l + (clipped - l) * (1 - l) / (x - l)
        }
        return clipped
    }

    /// W3C's `SetLum(C, l)`.
    private static func setLum(_ c: SIMD3<Double>, _ l: Double) -> SIMD3<Double> {
        clipColor(c + (l - lum(c)))
    }

    /// W3C's `Sat(C)`.
    private static func sat(_ c: SIMD3<Double>) -> Double {
        c.max() - c.min()
    }

    /// W3C's `SetSat(C, s)`: the largest channel becomes `s`, the smallest 0 and the middle
    /// one keeps its place between them.
    private static func setSat(_ c: SIMD3<Double>, _ s: Double) -> SIMD3<Double> {
        let high = c.max()
        let low = c.min()
        guard high > low else { return SIMD3(repeating: 0) }
        return (c - low) * s / (high - low)
    }
}
