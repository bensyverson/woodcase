//
//  PenTextNaturalLineHeightTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A text node with no `lineHeight` sets its lines at the font's natural height, and Pen
/// rounds that height to a whole point per line: `round(ascent + descent + leading)`.
///
/// Core Text rounds differently — Inter at 16 pt is 15.5 + 3.86 = 19.36, which Pen sets
/// as 19 and a bare `CTFramesetter` as 20 — so every line of Inter at 14 and 16 pt ran
/// one point tall, and a screen of it drifted downward line by line. The fallback face
/// hid this: SF Pro at 16 pt is 19.09, which both round to 19.
///
/// The expected heights are Pen's own, from `text-natural-line-height.layout.json`
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/text-natural-line-height.pen`,
/// pen CLI 0.3.9, 2026-09-26): one line and three lines of Inter at 12–32 pt.
struct PenTextNaturalLineHeightTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    @Test("An auto-height text node is as tall as Pen sets it")
    func layoutMatchesPen() throws {
        let document = try PenParser.parse(
            contentsOf: Self.fixtures.appendingPathComponent("text-natural-line-height.pen")
        )
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("text-natural-line-height.layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        let textIDs = expected.keys.filter { $0 != "prbA1" }.sorted()
        #expect(textIDs.count == 16)
        for id in textIDs {
            let rect = try #require(actual[id], "no rect for \(id)")
            let pen = try #require(expected[id])
            #expect(rect.height == pen.height, "\(id): Woodcase \(rect.height), Pen \(pen.height)")
        }
    }

    @Test("The renderer sets lines at the pitch the measurer reports")
    func rendererLinePitchMatchesPen() throws {
        // Three lines of 16 pt Inter: Pen's pitch is 19, so the third line's cap tops sit
        // 38 pt below the first's. Rendered at 4x so a pitch of 20 (80 px apart) cannot
        // round onto 19 (76 px).
        let scale = 4
        let data = PenNode.TextData(
            content: .literal("H\nH\nH"),
            fontFamily: .literal("Inter"),
            fontSize: .literal(16),
            fills: .single(.shorthand("#000000"))
        )
        let node = PenNode(id: "t", common: PenNodeCommon(), kind: .text(data))
        let rect = PenRect(x: 0, y: 0, width: 40, height: 80)
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [node]),
            layoutRects: [node.id: rect],
            size: CGSize(width: 40, height: 80),
            scale: CGFloat(scale)
        ))
        let tops = try inkRunTops(in: image)
        #expect(tops.count == 3, "ink runs start at rows \(tops)")
        let pitch = Double(tops[2] - tops[0]) / Double(2 * scale)
        #expect(abs(pitch - 19) <= 0.25, "line pitch \(pitch) pt, Pen's is 19")
    }

    /// The first row of each vertical run of rows that hold ink.
    private func inkRunTops(in image: CGImage) throws -> [Int] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var tops: [Int] = []
        var inRun = false
        for row in 0 ..< height {
            let hasInk = (0 ..< width).contains { pixels[(row * width + $0) * 4 + 3] > 127 }
            if hasInk, !inRun { tops.append(row) }
            inRun = hasInk
        }
        return tops
    }
}
