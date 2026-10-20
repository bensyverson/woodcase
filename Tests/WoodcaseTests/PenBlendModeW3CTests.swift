//
//  PenBlendModeW3CTests.swift
//  Woodcase
//

import Testing
@testable import Woodcase

/// The reference renderer's blend formulas follow W3C Compositing and Blending Level 1
/// (https://www.w3.org/TR/compositing-1/), and linear burn and linear dodge Photoshop's
/// `max(0, Cb + Cs − 1)` and `min(1, Cb + Cs)` (Ben's ruling, 2026-10-20). Each expected
/// value is worked from the spec's formula in the test's comment.
struct PenBlendModeW3CTests {
    private static let tolerance = 1e-9

    private static func gray(_ v: Double) -> SIMD3<Double> {
        SIMD3(repeating: v)
    }

    private static func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        let d = a - b
        return abs(d.x) < tolerance && abs(d.y) < tolerance && abs(d.z) < tolerance
    }

    private static func close(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> Bool {
        close(SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z)) && abs(a.w - b.w) < tolerance
    }

    private static func blend(_ mode: PenBlendMode, _ cb: Double, _ cs: Double) -> SIMD3<Double> {
        mode.blend(backdrop: gray(cb), source: gray(cs))
    }

    // MARK: - Separable modes

    /// Cb = 0.25, Cs = 0.5: darken min = 0.25; multiply 0.125; lighten max = 0.5; screen
    /// 0.25 + 0.5 − 0.125 = 0.625; difference 0.25; exclusion 0.25 + 0.5 − 2·0.125 = 0.5.
    @Test(arguments: [
        (PenBlendMode.darken, 0.25), (.multiply, 0.125), (.light, 0.5), (.screen, 0.625),
        (.difference, 0.25), (.exclusion, 0.5),
    ])
    func `The simple separable modes take W3C's formulas`(mode: PenBlendMode, expected: Double) {
        #expect(Self.close(Self.blend(mode, 0.25, 0.5), Self.gray(expected)), "\(mode)")
    }

    /// Cs ≤ 0.5: B = Cb − (1 − 2·Cs)·Cb·(1 − Cb) = 0.6 − 0.5·0.6·0.4 = 0.48.
    @Test func `Soft light with a dark source darkens by W3C's formula`() {
        #expect(Self.close(Self.blend(.softLight, 0.6, 0.25), Self.gray(0.48)))
    }

    /// Cs > 0.5, Cb > 0.25: D = √Cb = 0.8, B = Cb + (2·Cs − 1)·(D − Cb) = 0.64 + 0.5·0.16 = 0.72.
    @Test func `Soft light with a light source over a mid backdrop takes the square root`() {
        #expect(Self.close(Self.blend(.softLight, 0.64, 0.75), Self.gray(0.72)))
    }

    /// Cs > 0.5, Cb ≤ 0.25: D = ((16·Cb − 12)·Cb + 4)·Cb = ((2 − 12)·0.125 + 4)·0.125 = 0.34375,
    /// B = 0.125 + 1·(0.34375 − 0.125) = 0.34375 — Photoshop's √Cb would give 0.3536.
    @Test func `Soft light over a dark backdrop takes W3C's polynomial, not the square root`() {
        #expect(Self.close(Self.blend(.softLight, 0.125, 1), Self.gray(0.34375)))
    }

    /// B = min(1, Cb / (1 − Cs)): 0.3 / 0.5 = 0.6; Cb = 0 gives 0; Cs = 1 gives 1.
    @Test func `Color dodge divides by the inverted source, with W3C's edge cases`() {
        #expect(Self.close(Self.blend(.colorDodge, 0.3, 0.5), Self.gray(0.6)))
        #expect(Self.close(Self.blend(.colorDodge, 0, 1), Self.gray(0)))
        #expect(Self.close(Self.blend(.colorDodge, 0.3, 1), Self.gray(1)))
    }

    /// B = 1 − min(1, (1 − Cb) / Cs): 1 − 0.2 / 0.5 = 0.6; Cb = 1 gives 1; Cs = 0 gives 0.
    @Test func `Color burn divides the inverted backdrop by the source, with W3C's edge cases`() {
        #expect(Self.close(Self.blend(.colorBurn, 0.8, 0.5), Self.gray(0.6)))
        #expect(Self.close(Self.blend(.colorBurn, 1, 0), Self.gray(1)))
        #expect(Self.close(Self.blend(.colorBurn, 0.8, 0), Self.gray(0)))
    }

    /// B = max(0, Cb + Cs − 1): 0.75 + 0.5 − 1 = 0.25; 0.25 + 0.5 − 1 clamps to 0.
    @Test func `Linear burn adds and subtracts one, clamped at zero`() {
        #expect(Self.close(Self.blend(.linearBurn, 0.75, 0.5), Self.gray(0.25)))
        #expect(Self.close(Self.blend(.linearBurn, 0.25, 0.5), Self.gray(0)))
    }

    /// B = min(1, Cb + Cs): 0.25 + 0.5 = 0.75; 0.75 + 0.5 clamps to 1 — an add, not a screen
    /// (which would give 0.625 and 0.875).
    @Test func `Linear dodge adds, clamped at one`() {
        #expect(Self.close(Self.blend(.linearDodge, 0.25, 0.5), Self.gray(0.75)))
        #expect(Self.close(Self.blend(.linearDodge, 0.75, 0.5), Self.gray(1)))
    }

    /// Overlay is hard light with the operands swapped: Cb = 0.25 ≤ 0.5, so
    /// B = Cs·2·Cb = 0.8·0.5 = 0.4. Hard light, Cs = 0.75 > 0.5: Screen(Cb, 2·Cs − 1) =
    /// Screen(0.5, 0.5) = 0.75.
    @Test func `Overlay and hard light take W3C's formulas`() {
        #expect(Self.close(Self.blend(.overlay, 0.25, 0.8), Self.gray(0.4)))
        #expect(Self.close(Self.blend(.hardLight, 0.5, 0.75), Self.gray(0.75)))
    }

    @Test func `Normal and an unknown mode blend to the source`() {
        let cs = SIMD3(0.1, 0.2, 0.3)
        #expect(Self.close(PenBlendMode.normal.blend(backdrop: Self.gray(0.9), source: cs), cs))
        #expect(Self.close(PenBlendMode.unknown("x").blend(backdrop: Self.gray(0.9), source: cs), cs))
    }

    // MARK: - Non-separable modes

    /// SetLum(Cb, Lum(Cs)): Lum(1, 0, 0) = 0.3, so a 0.5 gray backdrop becomes 0.3 gray.
    @Test func `Luminosity keeps the backdrop's hue and saturation at the source's luminosity`() {
        let b = PenBlendMode.luminosity.blend(backdrop: Self.gray(0.5), source: SIMD3(1, 0, 0))
        #expect(Self.close(b, Self.gray(0.3)), "\(b)")
    }

    /// SetLum((1, 0, 0), 0.5) = ClipColor(1.2, 0.2, 0.2); l = 0.5, x = 1.2 > 1, so each
    /// channel is l + (C − l)·(1 − l)/(x − l): red 1, green and blue 0.5 − 0.3·0.5/0.7 = 2/7.
    @Test func `Color takes the source's hue and saturation, clipped into range`() {
        let b = PenBlendMode.color.blend(backdrop: Self.gray(0.5), source: SIMD3(1, 0, 0))
        #expect(Self.close(b, SIMD3(1, 2.0 / 7, 2.0 / 7)), "\(b)")
    }

    /// Sat of a gray backdrop is 0, so SetSat(Cs, 0) is black and SetLum lifts it to the
    /// backdrop's 0.5.
    @Test func `Hue over a gray backdrop keeps the gray`() {
        let b = PenBlendMode.hue.blend(backdrop: Self.gray(0.5), source: SIMD3(1, 0, 0))
        #expect(Self.close(b, Self.gray(0.5)), "\(b)")
    }

    /// SetSat(Cb, Sat(gray) = 0) is black; SetLum to Lum(0.8, 0.4, 0.2) =
    /// 0.24 + 0.236 + 0.022 = 0.498.
    @Test func `Saturation from a gray source desaturates the backdrop at its luminosity`() {
        let b = PenBlendMode.saturation.blend(backdrop: SIMD3(0.8, 0.4, 0.2), source: Self.gray(0.7))
        #expect(Self.close(b, Self.gray(0.498)), "\(b)")
    }

    // MARK: - Composite

    @Test func `A source over a transparent backdrop composites to itself`() {
        let source = SIMD4(0.1, 0.2, 0.4, 0.5)
        let out = PenBlendMode.softLight.composite(source: source, over: SIMD4(repeating: 0))
        #expect(Self.close(out, source), "\(out)")
    }

    @Test func `A transparent source leaves the backdrop`() {
        let backdrop = SIMD4(0.36, 0.24, 0.12, 0.4)
        let out = PenBlendMode.colorDodge.composite(source: SIMD4(repeating: 0), over: backdrop)
        #expect(Self.close(out, backdrop), "\(out)")
    }

    /// Cs = (0.2, 0.4, 1), αs = 1 over Cb = (0.9, 0.6, 0.3) at αb = 0.4:
    /// co = (1 − αb)·Cs + αb·min(1, Cb + Cs) = 0.6·(0.2, 0.4, 1) + 0.4·(1, 1, 1) = (0.52, 0.64, 1).
    @Test func `Linear dodge over a translucent backdrop weighs the blend by the backdrop's alpha`() {
        let out = PenBlendMode.linearDodge.composite(
            source: SIMD4(0.2, 0.4, 1, 1), over: SIMD4(0.36, 0.24, 0.12, 0.4)
        )
        #expect(Self.close(out, SIMD4(0.52, 0.64, 1, 1)), "\(out)")
    }

    /// Cs = (0.2, 0.4, 1) at αs = 0.5 over opaque Cb = (0.9, 0.6, 0.3):
    /// B = (min(1, 0.9/0.8), min(1, 0.6/0.6), 1) = (1, 1, 1);
    /// co = αs·B + (1 − αs)·Cb = (0.95, 0.8, 0.65), αo = 1.
    @Test func `Color dodge from a translucent source mixes the blend by the source's alpha`() {
        let out = PenBlendMode.colorDodge.composite(
            source: SIMD4(0.1, 0.2, 0.5, 0.5), over: SIMD4(0.9, 0.6, 0.3, 1)
        )
        #expect(Self.close(out, SIMD4(0.95, 0.8, 0.65, 1)), "\(out)")
    }

    /// Normal at αs = 0.5 is plain source-over: 0.5·(0.2, 0.4, 1) + 0.5·(0.9, 0.6, 0.3).
    @Test func `Normal composites as source-over`() {
        let out = PenBlendMode.normal.composite(source: SIMD4(0.1, 0.2, 0.5, 0.5), over: SIMD4(0.9, 0.6, 0.3, 1))
        #expect(Self.close(out, SIMD4(0.55, 0.5, 0.65, 1)), "\(out)")
    }

    /// αo = αs + αb·(1 − αs) = 0.5 + 0.4·0.5 = 0.7, not the 0.9 a plus operator sums to.
    @Test func `The output alpha is source-over's, whatever the mode`() {
        let out = PenBlendMode.linearDodge.composite(
            source: SIMD4(0.1, 0.2, 0.5, 0.5), over: SIMD4(0.36, 0.24, 0.12, 0.4)
        )
        #expect(abs(out.w - 0.7) < Self.tolerance, "\(out)")
    }
}
