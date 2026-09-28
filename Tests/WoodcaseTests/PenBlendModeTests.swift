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

    @Test("linearBurn maps to CGBlendMode.multiply (closest approximation)")
    func linearBurn() {
        #expect(PenBlendMode.linearBurn.cgBlendMode == .multiply)
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

    @Test("linearDodge maps to CGBlendMode.screen (closest approximation)")
    func linearDodge() {
        #expect(PenBlendMode.linearDodge.cgBlendMode == .screen)
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
}
