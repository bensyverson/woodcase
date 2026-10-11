//
//  PenTextSpansRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// The CG renderer draws a text node's runs: each in its own face and color, the rest in the
/// node's paint. There is no Pen reference for this — Pen cannot draw runs — so the gates are
/// the pixels' colors and the ink's extent.
struct PenTextSpansRenderTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let size = CGSize(width: 320, height: 60)
    private static let text = "RED black"
    private static let red = PenHexColor(red: 255, green: 0, blue: 0)

    private static func render(
        _ runs: [PenTextRun], text: String = text, family: String = "Inter",
        fills: PenFills? = .single(.shorthand("#000000"))
    ) throws -> PenFillDomainTests.RGBA {
        let node = PenNode.text(PenNode.TextData(
            content: .literal(text), fontFamily: .literal(family), fontSize: .literal(32), fills: fills
        ), spans: PenTextSpans(text: text, runs: runs))
        let document = PenDocument(version: "2.20", children: [node])
        let rect = PenRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
        let image = try #require(PenRenderer.render(document, layoutRects: ["t": rect], size: size))
        return try #require(PenFillDomainTests.RGBA(image))
    }

    /// The x where the run "RED" ends, in the node's box.
    private static var runEnd: Int {
        runEnd(family: "Inter")
    }

    /// The x where the run "RED" ends in `family`, in the node's box.
    private static func runEnd(family: String) -> Int {
        let layout = PenTextLayout(text: "RED", style: PenTextStyle(fontFamily: family, fontSize: 32), box: size)
        return Int(CTLineGetTypographicBounds(layout.lines.lines[0], nil, nil, nil).rounded(.down))
    }

    /// Counts the strongly colored pixels in columns `range`: reddish and dark.
    private static func count(in pixels: PenFillDomainTests.RGBA, columns range: Range<Int>) -> (red: Int, dark: Int) {
        var red = 0, dark = 0
        for y in 0 ..< pixels.height {
            for x in range {
                let pixel = pixels.pixel(x, y)
                guard pixel.a > 200 else { continue }
                if pixel.r > 200, pixel.g < 60, pixel.b < 60 { red += 1 }
                if pixel.r < 60, pixel.g < 60, pixel.b < 60 { dark += 1 }
            }
        }
        return (red, dark)
    }

    @Test("A colored run draws in its color; the rest in the node's")
    func coloredRun() throws {
        let pixels = try Self.render([PenTextRun(start: 0, end: 3, fill: Self.red)])
        let run = Self.count(in: pixels, columns: 0 ..< Self.runEnd)
        let rest = Self.count(in: pixels, columns: Self.runEnd + 4 ..< pixels.width)
        #expect(run.red > 50)
        #expect(run.dark == 0)
        #expect(rest.dark > 50)
        #expect(rest.red == 0)
    }

    @Test("A bold run lays down more ink than the same text plain")
    func boldRunInk() throws {
        let plain = try Self.render([])
        let bold = try Self.render([PenTextRun(start: 0, end: 3, fontWeight: 900)])
        let plainInk = Self.count(in: plain, columns: 0 ..< Self.runEnd).dark
        let boldInk = Self.count(in: bold, columns: 0 ..< Self.runEnd).dark
        #expect(boldInk > plainInk + 50)
    }

    /// SF Pro, because the test fonts' Inter has no italic face.
    @Test("An italic run draws differently from the same text upright")
    func italicRun() throws {
        let plain = try Self.render([], family: "SF Pro")
        let italic = try Self.render([PenTextRun(start: 0, end: 3, isItalic: true)], family: "SF Pro")
        var differing = 0
        for y in 0 ..< plain.height {
            for x in 0 ..< Self.runEnd(family: "SF Pro") where plain.pixel(x, y) != italic.pixel(x, y) {
                differing += 1
            }
        }
        #expect(differing > 100)
    }

    @Test("A node with no paint draws only its colored runs")
    func unpaintedNodeDrawsOwnFills() throws {
        let pixels = try Self.render([PenTextRun(start: 0, end: 3, fill: Self.red)], fills: nil)
        #expect(Self.count(in: pixels, columns: 0 ..< Self.runEnd).red > 50)
        var restInk = 0
        for y in 0 ..< pixels.height {
            for x in Self.runEnd + 4 ..< pixels.width where pixels.pixel(x, y).a > 0 {
                restInk += 1
            }
        }
        #expect(restInk == 0)
    }

    @Test("A colored run keeps its color inside a gradient-painted node")
    func coloredRunInGradient() throws {
        let gradient = PenFills.single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            colors: [
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#00FF00"), position: .literal(1)),
            ]
        )))
        let pixels = try Self.render([PenTextRun(start: 0, end: 3, fill: Self.red)], fills: gradient)
        #expect(Self.count(in: pixels, columns: 0 ..< Self.runEnd).red > 50)
        var restRed = 0, restInk = 0
        for y in 0 ..< pixels.height {
            for x in Self.runEnd + 4 ..< pixels.width {
                let pixel = pixels.pixel(x, y)
                guard pixel.a > 200 else { continue }
                restInk += 1
                if pixel.r > 200, pixel.g < 60, pixel.b < 60 { restRed += 1 }
            }
        }
        #expect(restInk > 50)
        #expect(restRed == 0)
    }

    @Test("An underlined run draws a bar under its own words only")
    func underlinedRun() throws {
        let plain = try Self.render([])
        let underlined = try Self.render([PenTextRun(start: 4, end: 9, underline: true)])
        var underRun = 0, underRed = 0
        for y in 0 ..< plain.height {
            for x in 0 ..< plain.width where plain.pixel(x, y) != underlined.pixel(x, y) {
                if x < Self.runEnd { underRed += 1 } else { underRun += 1 }
            }
        }
        #expect(underRun > 50)
        #expect(underRed == 0)
    }
}
