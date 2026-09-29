//
//  ActorColorTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

/// The identity color, pinned against the Jobs dashboard's own values.
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
