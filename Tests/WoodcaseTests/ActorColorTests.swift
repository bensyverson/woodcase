//
//  ActorColorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The identity color, pinned against the Jobs dashboard's own values.
///
/// It lives in the Woodcase library so the note look, the viewer and Penumbra draw one
/// color per identity (Penumbra's notes design, decision 7, ruled 2026-10-11).
///
/// The whole point of porting the hash is that an agent is the same color in both
/// tools, so these two rows are a contract with `jobs/internal/web/render/actor_color.go`
/// and not merely a regression guard.
struct ActorColorTests {
    @Test("claude-a hashes to the Jobs dashboard's green")
    func claudeAMatchesJobs() {
        let color = ActorColor(name: "claude-a")
        #expect(color.hue == 152)
        #expect(color.saturation == 85)
        #expect(color.lightness == 48)
        #expect(color.css == "hsl(152 85% 48%)")
        #expect(color.hex == "#12E281")
    }

    @Test("ben hashes to the Jobs dashboard's softer green")
    func benMatchesJobs() {
        let color = ActorColor(name: "ben")
        #expect(color.hue == 149)
        #expect(color.saturation == 60)
        #expect(color.css == "hsl(149 60% 48%)")
        #expect(color.hex == "#31C478")
    }

    /// More names, each pinned to what the Jobs dashboard's own Go prints. The hue and
    /// saturation come from running `actor_color.go`'s `ActorColor` verbatim (`go run`,
    /// 2026-10-11); the hex from Python's `colorsys.hls_to_rgb` at 48% lightness, an HSL
    /// conversion independent of this type's.
    @Test(
        "More names match the Jobs dashboard's hsl and its hex",
        arguments: [
            ("claude", "hsl(6 55% 48%)", "#BE4537"),
            ("codex", "hsl(91 74% 48%)", "#77D520"),
            ("ana", "hsl(192 51% 48%)", "#3CA0B9"),
            ("w-look", "hsl(165 52% 48%)", "#3BBA9A"),
            ("Ben Syverson", "hsl(84 79% 48%)", nil),
            ("", "hsl(328 93% 48%)", nil),
        ] as [(String, String, String?)]
    )
    func moreNamesMatchJobs(name: String, css: String, hex: String?) {
        let color = ActorColor(name: name)
        #expect(color.css == css)
        if let hex { #expect(color.hex == hex) }
    }

    @Test("The color as a PenHexColor is the hex, opaque")
    func colorIsTheHex() {
        let color = ActorColor(name: "claude")
        #expect(color.color == PenHexColor("#BE4537"))
        #expect(color.color.alpha == 255)
    }

    @Test("The ink as a color is black or white, opaque")
    func inkColor() {
        #expect(ActorColor.Ink.black.color == PenHexColor("#000000"))
        #expect(ActorColor.Ink.white.color == PenHexColor("#FFFFFF"))
    }

    @Test("Any fill picks its ink by the same pivot, so a chosen color is lettered legibly")
    func inkOnAnyFill() throws {
        #expect(try ActorColor.Ink(on: #require(PenHexColor("#12E281"))) == .black)
        #expect(try ActorColor.Ink(on: #require(PenHexColor("#150AEB"))) == .white)
        #expect(ActorColor.Ink(on: ActorColor(name: "claude").color) == ActorColor(name: "claude").ink)
    }

    @Test("FNV-1a is the 32-bit variant, seeded and multiplied by the standard constants")
    func hashIsFNV1a32() {
        #expect(ActorColor.hash("") == 2_166_136_261)
        #expect(ActorColor.hash("a") == 0xE40C_292C)
    }

    @Test("Saturation never leaves the 50–99 band the palette is designed for")
    func saturationStaysInBand() {
        for index in 0 ..< 500 {
            let color = ActorColor(name: "agent-\(index)")
            #expect(color.saturation >= 50)
            #expect(color.saturation <= 99)
            #expect(color.hue >= 0)
            #expect(color.hue < 360)
        }
    }

    @Test("The initial is the first letter, uppercased")
    func initialIsFirstLetter() {
        #expect(ActorColor(name: "claude-a").initial == "C")
        #expect(ActorColor(name: "ben").initial == "B")
        #expect(ActorColor(name: "9lives").initial == "9")
    }

    @Test("An empty name still yields a color and a placeholder initial")
    func emptyNameIsSafe() {
        let color = ActorColor(name: "")
        #expect(color.initial == "?")
        #expect(color.css.hasPrefix("hsl("))
    }

    // MARK: - The ink

    @Test("A bright disc takes black ink")
    func brightDiscTakesBlack() {
        // hsl(152 85% 48%) — the green `claude-a` has had since the dashboard hashed it.
        let color = ActorColor(name: "claude-a")
        #expect(color.hex == "#12E281")
        #expect(color.ink == .black)
    }

    @Test("A dark disc takes white ink")
    func darkDiscTakesWhite() {
        // hsl(243 92% 48%) — the same 48% lightness, a fifth of the luminance.
        let color = ActorColor(name: "claude-b")
        #expect(color.hex == "#150AEB")
        #expect(color.ink == .white)
    }

    @Test(
        "Every hue on the wheel reaches AA with the ink it picks",
        arguments: [50, 99]
    )
    func everyHueReachesAA(saturation: Int) {
        for hue in 0 ..< 360 {
            let (red, green, blue) = ActorColor.rgb(
                hue: Double(hue), saturation: Double(saturation) / 100, lightness: 0.48
            )
            let ink = ActorColor.ink(red: red, green: green, blue: blue)
            let ratio = Self.contrast(
                Self.luminance(red: red, green: green, blue: blue),
                ink == .black ? 0 : 1
            )
            #expect(
                ratio >= 4.5,
                "hsl(\(hue) \(saturation)% 48%) reads \(ink) at \(ratio)"
            )
        }
    }

    /// WCAG 2.x relative luminance, written out here rather than borrowed from the
    /// type under test: a test that reuses the implementation's own math proves the
    /// two agree, not that either is right.
    ///
    /// - Parameters:
    ///   - red: The red channel, `0 ... 255`.
    ///   - green: The green channel, `0 ... 255`.
    ///   - blue: The blue channel, `0 ... 255`.
    /// - Returns: The relative luminance, `0 ... 1`.
    static func luminance(red: Int, green: Int, blue: Int) -> Double {
        func channel(_ value: Int) -> Double {
            let scaled = Double(value) / 255
            return scaled <= 0.04045 ? scaled / 12.92 : pow((scaled + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// The WCAG contrast ratio between two relative luminances.
    ///
    /// - Parameters:
    ///   - one: One luminance.
    ///   - other: The other.
    /// - Returns: The ratio, `1 ... 21`.
    static func contrast(_ one: Double, _ other: Double) -> Double {
        (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }
}
