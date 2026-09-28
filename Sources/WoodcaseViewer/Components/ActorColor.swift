//
//  ActorColor.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The colour an identity is drawn in, hashed from its name.
///
/// Ported from the Jobs dashboard's `internal/web/render/actor_color.go` so an agent is
/// the same colour in both tools — which is the whole reason the formula is a hash and
/// not a palette index: two processes that never talk agree without coordinating.
///
/// ```swift
/// ActorColor(name: "claude-a").css   // "hsl(152 85% 48%)"
/// ActorColor(name: "ben").hex        // "#31C478"
/// ActorColor(name: "claude-b").ink   // .white — a blue disc, unlike the two above
/// ```
///
/// ## The ink is Woodcase's own
///
/// The hash is the dashboard's, byte for byte. ``ink`` is not: the dashboard draws white
/// on every disc, and at 48% lightness a green one is white-on-green at 1.7:1. The pivot
/// below reaches AA on every hue the hash can produce **without touching the hash**,
/// which is the only reason it is a second property rather than a different lightness.
///
/// ## Where the colour may appear
///
/// In the avatar disc and in the edit markers over the render — nowhere else. A hashed
/// hue lands on the accent green often enough (`claude-a` and `ben` both do) that
/// coloured *text* would read as a link or as liveness. That rule is the design's, not
/// this type's, but it is the reason ``css`` is offered as a custom property rather than
/// as a class.
public struct ActorColor: Friendly {
    /// The colour for an identity.
    ///
    /// - Parameter name: The `--as` name the identity writes under.
    public init(name: String) {
        self.name = name
        hue = Int(Self.hash(name + "u") % 360)
        saturation = Int(Self.hash(name + "zzzzzzzz") % 50) + 50
    }

    /// The identity's name.
    public let name: String

    /// The hue in degrees, `0 ..< 360`.
    public let hue: Int

    /// The saturation as a percentage, `50 ... 99` — the band that keeps every hue
    /// legible as a small filled disc.
    public let saturation: Int

    /// The lightness every actor colour is drawn at, as a percentage.
    ///
    /// Fixed rather than hashed: it is what makes white text legible on every disc, and
    /// what keeps two identities distinguishable by hue rather than by brightness.
    public var lightness: Int {
        48
    }

    /// The colour as a CSS `hsl()` function.
    public var css: String {
        "hsl(\(hue) \(saturation)% \(lightness)%)"
    }

    /// The same colour as a `#RRGGBB` hex string, for a context that cannot take a
    /// function — an SVG attribute, a test's expected value.
    public var hex: String {
        let (red, green, blue) = Self.rgb(hue: Double(hue), saturation: Double(saturation) / 100, lightness: Double(lightness) / 100)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// The two inks a filled disc can be lettered in.
    ///
    /// Two values rather than a `Bool`, because "is this disc light?" is a question about
    /// the fill and this is an answer about the letter: the raw value is the colour to
    /// write, so a caller never re-derives one from the other.
    public enum Ink: String, Friendly, CaseIterable {
        /// `#000000`, for a disc bright enough to read black on.
        case black = "#000000"
        /// `#FFFFFF`, for a disc dark enough to read white on.
        case white = "#FFFFFF"
    }

    /// The ink the initial is drawn in on this disc.
    ///
    /// Black above a relative luminance of ``inkThreshold``, white below — the crossing
    /// point where both inks clear WCAG AA, so every hue the hash can reach is legible
    /// with the hue, the saturation and the 48% lightness left exactly as they are.
    public var ink: Ink {
        let (red, green, blue) = Self.rgb(
            hue: Double(hue), saturation: Double(saturation) / 100, lightness: Double(lightness) / 100
        )
        return Self.ink(red: red, green: green, blue: blue)
    }

    /// The relative luminance at which black ink overtakes white.
    ///
    /// Solving `(L + 0.05) / 0.05 = 1.05 / (L + 0.05)` gives `√1.05 − 0.05 ≈ 0.179`: at
    /// that fill both inks land on 4.58:1, and either side of it the better one is
    /// better still. It is a two-way threshold, so there is no band where neither works.
    static let inkThreshold = 0.179

    /// The ink a fill of these channels takes.
    ///
    /// - Parameters:
    ///   - red: The red channel, `0 ... 255`.
    ///   - green: The green channel, `0 ... 255`.
    ///   - blue: The blue channel, `0 ... 255`.
    /// - Returns: Black if the fill is bright enough, white otherwise.
    static func ink(red: Int, green: Int, blue: Int) -> Ink {
        relativeLuminance(red: red, green: green, blue: blue) > inkThreshold ? .black : .white
    }

    /// WCAG 2.x relative luminance: the sRGB channels linearised and weighted.
    ///
    /// - Parameters:
    ///   - red: The red channel, `0 ... 255`.
    ///   - green: The green channel, `0 ... 255`.
    ///   - blue: The blue channel, `0 ... 255`.
    /// - Returns: The luminance, `0 ... 1`.
    static func relativeLuminance(red: Int, green: Int, blue: Int) -> Double {
        func linear(_ channel: Int) -> Double {
            let scaled = Double(channel) / 255
            return scaled <= 0.04045 ? scaled / 12.92 : pow((scaled + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The letter drawn inside the disc: the name's first character, uppercased.
    ///
    /// An empty name gets `?` — an unattributed write is a real state (an editor that
    /// does not log saved the file), and a blank disc would read as a rendering bug.
    public var initial: String {
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    /// FNV-1a, 32-bit.
    ///
    /// Spelled out rather than taken from `Hasher`, which is seeded per process: the
    /// colour has to be the same in this viewer, in the Jobs dashboard, and after a
    /// restart.
    ///
    /// - Parameter text: The string to hash.
    /// - Returns: The 32-bit digest.
    static func hash(_ text: String) -> UInt32 {
        var digest: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            digest ^= UInt32(byte)
            digest = digest &* 16_777_619
        }
        return digest
    }

    /// Converts HSL to 8-bit RGB, the standard way.
    ///
    /// - Parameters:
    ///   - hue: Degrees, `0 ..< 360`.
    ///   - saturation: `0 ... 1`.
    ///   - lightness: `0 ... 1`.
    /// - Returns: The three channels, `0 ... 255`.
    static func rgb(hue: Double, saturation: Double, lightness: Double) -> (Int, Int, Int) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = lightness - chroma / 2

        let (red, green, blue): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, second, 0)
        case 1: (second, chroma, 0)
        case 2: (0, chroma, second)
        case 3: (0, second, chroma)
        case 4: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        return (
            Int(((red + offset) * 255).rounded()),
            Int(((green + offset) * 255).rounded()),
            Int(((blue + offset) * 255).rounded())
        )
    }
}
