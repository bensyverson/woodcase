//
//  PostItLookTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The values the rev 2 look is drawn from: the tint presets, the ink chosen by the paper's
/// brightness.
/// Penumbra's notes design, decision 12, and spec §10.
struct PostItLookTests {
    @Test("Post-it yellow is the default tint, and the six presets of spec §10 follow it")
    func tintPresets() {
        #expect(PenPostIt.Tint.allCases.map(\.rawValue) == ["yellow", "pink", "orange", "green", "blue", "purple", "gray"])
        #expect(PenPostIt.Tint.yellow.color.hex == "#FFF59D")
        #expect(PenPostIt.Tint.default == .yellow)
        #expect(Set(PenPostIt.Tint.allCases.map(\.color)).count == PenPostIt.Tint.allCases.count)
        for tint in PenPostIt.Tint.allCases {
            #expect(tint.color.alpha == 255, "\(tint) is not opaque")
        }
    }

    @Test("Ink is black on light paper and white on dark, at the style's alphas")
    func inkByBrightness() throws {
        let style = PenPostIt.Style.standard
        let light = PenPostIt.Ink(on: PenPostIt.Tint.yellow.color, style: style)
        #expect(light == style.inkOnLight)
        let lightInks: [PenHexColor] = [light.primary, light.secondary, light.tertiary]
        #expect(lightInks.allSatisfy { (ink: PenHexColor) -> Bool in ink.red == 0 && ink.green == 0 && ink.blue == 0 })

        let dark = try PenPostIt.Ink(on: #require(PenHexColor("#37474F")), style: style)
        #expect(dark == style.inkOnDark)
        let darkInks: [PenHexColor] = [dark.primary, dark.secondary, dark.tertiary]
        #expect(darkInks.allSatisfy { (ink: PenHexColor) -> Bool in ink.red == 255 && ink.green == 255 && ink.blue == 255 })

        #expect(light.primary.alpha > light.secondary.alpha)
        #expect(light.secondary.alpha > light.tertiary.alpha)
    }

    @Test("Every preset tint takes black ink")
    func presetsTakeBlackInk() {
        for tint in PenPostIt.Tint.allCases {
            #expect(PenPostIt.Ink(on: tint.color, style: .standard) == PenPostIt.Style.standard.inkOnLight, "\(tint)")
        }
    }

    @Test("Relative luminance runs from black to white")
    func luminance() throws {
        #expect(try #require(PenHexColor("#000000")).relativeLuminance == 0)
        #expect(try abs(#require(PenHexColor("#FFFFFF")).relativeLuminance - 1) < 1e-9)
        let gray = try #require(PenHexColor("#777777")).relativeLuminance
        #expect(gray > 0.17 && gray < 0.2)
    }

    @Test("Mixing toward a color moves each channel by the fraction")
    func mixing() throws {
        let white = try #require(PenHexColor("#FFFFFF"))
        let black = try #require(PenHexColor("#000000"))
        #expect(white.mixed(toward: black, by: 0) == white)
        #expect(white.mixed(toward: black, by: 1) == black)
        #expect(white.mixed(toward: black, by: 0.5).red == 128)
    }
}
