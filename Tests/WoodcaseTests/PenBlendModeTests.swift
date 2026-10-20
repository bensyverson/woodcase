//
//  PenBlendModeTests.swift
//  Woodcase
//

import CoreGraphics
import Testing
@testable import Woodcase

struct PenBlendModeTests {
    @Test("normal maps to CGBlendMode.normal")
    func normal() {
        #expect(PenBlendMode.normal.cgBlendMode == .normal)
    }

    @Test("darken maps to CGBlendMode.darken")
    func darken() {
        #expect(PenBlendMode.darken.cgBlendMode == .darken)
    }

    @Test("multiply maps to CGBlendMode.multiply")
    func multiply() {
        #expect(PenBlendMode.multiply.cgBlendMode == .multiply)
    }

    /// Plus-darker is linear burn wherever both colors are opaque (and over a transparent
    /// backdrop); it was multiply, a different formula, before the 2026-10-20 ruling that
    /// linear burn is a true linear burn. The renderer draws it per pixel where it can.
    @Test("linearBurn maps to CGBlendMode.plusDarker, its opaque equivalent")
    func linearBurn() {
        #expect(PenBlendMode.linearBurn.cgBlendMode == .plusDarker)
    }

    @Test("colorBurn maps to CGBlendMode.colorBurn")
    func colorBurn() {
        #expect(PenBlendMode.colorBurn.cgBlendMode == .colorBurn)
    }

    @Test("light maps to CGBlendMode.lighten")
    func light() {
        #expect(PenBlendMode.light.cgBlendMode == .lighten)
    }

    @Test("screen maps to CGBlendMode.screen")
    func screen() {
        #expect(PenBlendMode.screen.cgBlendMode == .screen)
    }

    /// Plus-lighter is linear dodge (an add) wherever both colors are opaque; it was screen,
    /// a different formula, before the 2026-10-20 ruling. The renderer draws it per pixel
    /// where it can.
    @Test("linearDodge maps to CGBlendMode.plusLighter, its opaque equivalent")
    func linearDodge() {
        #expect(PenBlendMode.linearDodge.cgBlendMode == .plusLighter)
    }

    @Test("colorDodge maps to CGBlendMode.colorDodge")
    func colorDodge() {
        #expect(PenBlendMode.colorDodge.cgBlendMode == .colorDodge)
    }

    @Test("overlay maps to CGBlendMode.overlay")
    func overlay() {
        #expect(PenBlendMode.overlay.cgBlendMode == .overlay)
    }

    @Test("softLight maps to CGBlendMode.softLight")
    func softLight() {
        #expect(PenBlendMode.softLight.cgBlendMode == .softLight)
    }

    @Test("hardLight maps to CGBlendMode.hardLight")
    func hardLight() {
        #expect(PenBlendMode.hardLight.cgBlendMode == .hardLight)
    }

    @Test("difference maps to CGBlendMode.difference")
    func difference() {
        #expect(PenBlendMode.difference.cgBlendMode == .difference)
    }

    @Test("exclusion maps to CGBlendMode.exclusion")
    func exclusion() {
        #expect(PenBlendMode.exclusion.cgBlendMode == .exclusion)
    }

    @Test("hue maps to CGBlendMode.hue")
    func hue() {
        #expect(PenBlendMode.hue.cgBlendMode == .hue)
    }

    @Test("saturation maps to CGBlendMode.saturation")
    func saturation() {
        #expect(PenBlendMode.saturation.cgBlendMode == .saturation)
    }

    @Test("color maps to CGBlendMode.color")
    func color() {
        #expect(PenBlendMode.color.cgBlendMode == .color)
    }

    @Test("luminosity maps to CGBlendMode.luminosity")
    func luminosity() {
        #expect(PenBlendMode.luminosity.cgBlendMode == .luminosity)
    }

    @Test("unknown falls back to CGBlendMode.normal")
    func unknownFallback() {
        #expect(PenBlendMode.unknown("customMode").cgBlendMode == .normal)
    }

    // MARK: - Compositing

    /// The modes Core Graphics draws by W3C's formula at any alpha, to within 8-bit rounding
    /// (checked by sweeping colors and alphas against the formula, 2026-10-20).
    @Test(arguments: [
        PenBlendMode.normal, .darken, .multiply, .light, .screen, .overlay, .hardLight, .difference, .exclusion,
        .unknown("x"),
    ])
    func `Modes Core Graphics draws exactly composite through it`(mode: PenBlendMode) {
        #expect(mode.compositing == .coreGraphics)
    }

    /// The modes whose Core Graphics formula departs from W3C's: soft light always; color
    /// dodge and burn from a translucent source; plus-darker and plus-lighter over a
    /// translucent backdrop; the non-separable modes by a few steps everywhere.
    @Test(arguments: [
        PenBlendMode.linearBurn, .linearDodge, .colorBurn, .colorDodge, .softLight,
        .hue, .saturation, .color, .luminosity,
    ])
    func `Modes Core Graphics draws inexactly composite per pixel`(mode: PenBlendMode) {
        #expect(mode.compositing == .perPixel)
    }
}
