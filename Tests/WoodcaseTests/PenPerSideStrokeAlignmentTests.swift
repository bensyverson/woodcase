import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Per-side strokes against Pen's own renders, measured as geometry.
///
/// `render-per-side-strokes.pen` puts a white per-side stroke on a 200×120 node at
/// (60, 60) under each `strokeAlignment` — and none, which Pen draws as center — for
/// four width combinations, with square, rounded and per-corner-rounded boxes. The
/// references are Pen's 2x PNG exports (`scripts/pen-oracle … --scale 2`); the fixture
/// comes from `scripts/gen-paint-geometry-fixtures`.
///
/// Each case scans a set of rows and columns through the bands and the corners and
/// requires every band edge to sit within half a point of Pen's.
struct PenPerSideStrokeAlignmentTests {
    private static let fixture = "render-per-side-strokes"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2

    /// Every artboard of the fixture, in document order.
    private static let artboards = [
        "mixed-unset", "mixed-inner", "mixed-center", "mixed-outer",
        "sides-unset", "sides-inner", "sides-center", "sides-outer",
        "top-unset", "top-inner", "top-center", "top-outer",
        "even-unset", "even-inner", "even-center", "even-outer",
        "radius-unset", "radius-inner", "radius-center", "radius-outer",
        "corners-inner", "corners-center", "corners-outer",
        "small-radius-center", "rect-inner", "rect-outer",
    ]

    /// Scan lines in points: through each band, through the corners, and just outside the box.
    private static let rows: [Double] = [51, 53, 57, 59, 61, 63, 66, 72, 90, 120, 160, 172, 176, 179, 182, 186, 190, 196, 202]
    private static let columns: [Double] = [51, 55, 57, 59, 61, 64, 67, 72, 90, 160, 230, 250, 254, 258, 262, 266, 270, 274]

    /// The criterion: band edges within half a point of Pen's.
    private static let tolerance = 0.5

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each per-side case puts its band edges within 0.5 pt of Pen's, and its MAE within 0.28", arguments: artboards)
    func bandEdgesMatchPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        let ours = try #require(Coverage(rendered))
        let pens = try #require(Coverage(reference))
        #expect(ours.width == pens.width && ours.height == pens.height)

        for y in Self.rows {
            let row = Int(y * Double(Self.scale))
            compare(ours.edges(row: row), pens.edges(row: row), "\(artboard) row y=\(y)")
        }
        for x in Self.columns {
            let column = Int(x * Double(Self.scale))
            compare(ours.edges(column: column), pens.edges(column: column), "\(artboard) column x=\(x)")
        }
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Per-side stroke \(artboard) MAE: \(mae)")
        // max(measured×1.5, measured+0.25) over the worst case (`radius-outer`, 0.027).
        #expect(mae < 0.28, "\(artboard): MAE \(mae)")
    }

    private func compare(
        _ ours: [Double], _ pens: [Double], _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let scale = Double(Self.scale)
        let oursPt = ours.map { $0 / scale }
        let pensPt = pens.map { $0 / scale }
        guard oursPt.count == pensPt.count else {
            Issue.record("\(label): edges \(oursPt) against Pen's \(pensPt)", sourceLocation: sourceLocation)
            return
        }
        for (a, b) in zip(oursPt, pensPt) where abs(a - b) > Self.tolerance {
            Issue.record("\(label): edges \(oursPt) against Pen's \(pensPt)", sourceLocation: sourceLocation)
            return
        }
    }

    /// An image's coverage (luminance, 0…1) with sub-pixel run edges along a row or column.
    private struct Coverage {
        let width: Int
        let height: Int
        private let values: [Double]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            values = pixels.map { Double($0) / 255 }
        }

        func edges(row: Int) -> [Double] {
            Self.edges((0 ..< width).map { values[row * width + $0] })
        }

        func edges(column: Int) -> [Double] {
            Self.edges((0 ..< height).map { values[$0 * width + column] })
        }

        /// The start and end of each run of covered pixels, in pixels, refined by the
        /// partial coverage of the pixel on either side.
        private static func edges(_ line: [Double]) -> [Double] {
            var result: [Double] = []
            var index = 0
            while index < line.count {
                guard line[index] > 0.5 else {
                    index += 1
                    continue
                }
                let start = index
                while index < line.count, line[index] > 0.5 {
                    index += 1
                }
                result.append(Double(start) - (start > 0 ? line[start - 1] : 0))
                result.append(Double(index) + (index < line.count ? line[index] : 0))
            }
            return result
        }
    }
}
