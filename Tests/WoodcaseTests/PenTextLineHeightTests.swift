//
//  PenTextLineHeightTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Text with an explicit `lineHeight` is laid out and drawn as Pen sets it.
///
/// Pen follows CSS: every line box is `lineHeight × fontSize` tall, and the difference
/// between that and the font's ascent plus descent is split equally above and below the
/// glyphs (half-leading), negative when lines are tighter than the font.
///
/// The references are Pen's own: `render-text-line-height.layout.json` and the five
/// `render-text-line-height-*.png` exports at 2x (`scripts/pen-oracle
/// Tests/WoodcaseTests/Fixtures/render-text-line-height.pen`, pen CLI 0.3.9, 2026-09-27).
struct PenTextLineHeightTests {
    /// Every board sets Inter; without it they measure the fallback face.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixture = "render-text-line-height"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2
    private static let roundingFixture = "text-line-height-rounding"

    private static let boards = ["tight-wrap", "loose-wrap", "fixed-middle", "auto-tight", "stacked"]

    /// Each board's MAE ceiling at 2x, set by the margin rule (`max(measured × 1.5, measured + 0.25)`,
    /// `project/2026-09-26-mae-margin-rule.md`) from the figure beside it, measured 2026-09-27 with
    /// `swift test -j 3 --filter PenTextLineHeightTests`. Before lines were placed by half-leading and
    /// Inter kept its default optical size, the five boards scored 5.46–13.39.
    private static let maeCeilings: [String: Double] = [
        "tight-wrap": 2.37, // 1.574
        "loose-wrap": 1.59, // 1.053
        "fixed-middle": 0.33, // 0.074
        "auto-tight": 1.41, // 0.939
        "stacked": 1.91, // 1.272
        roundingFixture: 0.71, // 0.460
    ]

    @Test("Every node is laid out where Pen lays it out")
    func layoutMatchesPen() throws {
        let document = try PenParser.parse(
            contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
        )
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.fixture).layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        #expect(expected.count == 12)
        for id in expected.keys.sorted() {
            let rect = try #require(actual[id], "no rect for \(id)")
            let pen = try #require(expected[id])
            #expect(rect == pen, "\(id): Woodcase \(rect), Pen \(pen)")
        }
    }

    @Test("Each line's ink starts and ends where Pen's does, within the board's MAE ceiling", arguments: boards)
    func inkBandsMatchPen(board: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: board, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(board)", fixturesDir: Self.fixturesDir
        ))
        let ours = try InkBands(rendered)
        let pens = try InkBands(reference)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Line height \(board): MAE \(mae) \(rendered.width)x\(rendered.height) CG bands \(ours.bands), Pen bands \(pens.bands)")
        #expect(mae <= Self.maeCeilings[board]!, "\(board): MAE \(mae)")
        #expect(ours.bands.count == pens.bands.count, "\(board): CG \(ours.bands), Pen \(pens.bands)")
        for (mine, pen) in zip(ours.bands, pens.bands) {
            #expect(abs(mine.lowerBound - pen.lowerBound) <= 1, "\(board): top \(mine) against Pen's \(pen)")
            #expect(abs(mine.upperBound - pen.upperBound) <= 1, "\(board): bottom \(mine) against Pen's \(pen)")
        }
    }

    /// Pen rounds each line's pitch, not the text's height: 14 pt at 1.25 is 18 points a
    /// line, so three lines are 54 rather than 52.5 rounded up. The probe is Inter at five
    /// fractional pitches with one, two and three lines each (`text-line-height-rounding`,
    /// `scripts/pen-oracle`, pen CLI 0.3.9, 2026-09-27).
    @Test("A line's pitch is its line height rounded to a whole point")
    func pitchIsRoundedPerLine() throws {
        let document = try PenParser.parse(
            contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.roundingFixture).pen")
        )
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.roundingFixture).layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        #expect(expected.count == 16)
        for id in expected.keys.sorted() {
            let rect = try #require(actual[id], "no rect for \(id)")
            let pen = try #require(expected[id])
            #expect(rect == pen, "\(id): Woodcase \(rect), Pen \(pen)")
        }
    }

    /// At a fractional pitch the glyphs still sit where Pen's do.
    @Test("Lines at a fractional pitch put their ink where Pen's is, within the MAE ceiling")
    func roundedPitchInkMatchesPen() throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: "probe", in: Self.roundingFixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: Self.roundingFixture, fixturesDir: Self.fixturesDir
        ))
        let ours = try InkBands(rendered)
        let pens = try InkBands(reference)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Line height rounding: MAE \(mae) CG bands \(ours.bands), Pen bands \(pens.bands)")
        #expect(mae <= Self.maeCeilings[Self.roundingFixture]!, "MAE \(mae)")
        #expect(ours.bands.count == pens.bands.count, "CG \(ours.bands), Pen \(pens.bands)")
        for (mine, pen) in zip(ours.bands, pens.bands) {
            #expect(abs(mine.lowerBound - pen.lowerBound) <= 1, "top \(mine) against Pen's \(pen)")
            #expect(abs(mine.upperBound - pen.upperBound) <= 1, "bottom \(mine) against Pen's \(pen)")
        }
    }

    // MARK: - Helpers

    /// The vertical runs of pixel rows that hold dark ink, in pixels from the top.
    struct InkBands {
        let bands: [ClosedRange<Int>]

        init(_ image: CGImage) throws {
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var bands: [ClosedRange<Int>] = []
            var start: Int?
            for row in 0 ..< height {
                // Dark ink only: the boards' text is black or #333 on white, #E8E8E8 or #FF3300.
                let hasInk = (0 ..< width).contains { column in
                    let offset = (row * width + column) * 4
                    return pixels[offset] < 128 && pixels[offset + 1] < 128 && pixels[offset + 2] < 128
                }
                if hasInk, start == nil { start = row }
                if !hasInk, let first = start {
                    bands.append(first ... row - 1)
                    start = nil
                }
            }
            if let first = start { bands.append(first ... height - 1) }
            self.bands = bands
        }
    }
}
