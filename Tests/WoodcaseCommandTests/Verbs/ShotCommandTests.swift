//
//  ShotCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import PixelPeeper
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `shot` renders one node to a PNG sized to fit `--max`, and refuses to guess a node
/// when none is named.
@Suite("shot")
struct ShotCommandTests {
    // MARK: - Scale

    @Test("A node no larger than --max renders at 1×")
    func scaleIsOneWhenWithinMax() {
        #expect(Shot.effectiveScale(longestSide: 400, maxPoints: 1600) == 1)
    }

    @Test("A node larger than --max is shrunk, never enlarged past its own size")
    func scaleShrinksOversizedNodes() {
        #expect(Shot.effectiveScale(longestSide: 800, maxPoints: 400) == 0.5)
    }

    @Test("A zero-size node does not divide by zero")
    func scaleHandlesZeroSize() {
        #expect(Shot.effectiveScale(longestSide: 0, maxPoints: 1600) == 1)
    }

    // MARK: - The pixel size respects --max and the scale maps back to points

    @Test("A shot's pixel size respects --max and the printed scale maps back to layout points")
    func pixelSizeRespectsMaxAndScaleRoundTrips() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("dashboard.png").path

        // Dash1 "Dashboard" is 800×600 — below the default --max 1600, so scale is 1.
        let unscaled = try fixture.run("shot", fixture.file.path, "Dashboard", "--out", outputPath)
        #expect(unscaled.status == 0)
        let unscaledLine = try #require(unscaled.stdoutLines.first)
        #expect(unscaledLine.contains("scale=1.0"))
        #expect(unscaledLine.contains("rect=0.0,0.0,800.0,600.0"))
        #expect(unscaledLine.contains("pixels=800x600"))
        try #require(pixelSize(of: outputPath) == (800, 600))

        // The same node under --max 400 is shrunk to fit, scale 0.5, pixels halved.
        let scaledPath = fixture.root.appendingPathComponent("dashboard-small.png").path
        let scaled = try fixture.run(
            "shot", fixture.file.path, "Dashboard", "--out", scaledPath, "--max", "400"
        )
        #expect(scaled.status == 0)
        let scaledLine = try #require(scaled.stdoutLines.first)
        #expect(scaledLine.contains("scale=0.5"))
        #expect(scaledLine.contains("pixels=400x300"))
        try #require(pixelSize(of: scaledPath) == (400, 300))

        // point = pixel / scale + origin: pixel (400,300) on the scaled image is the
        // rect's own bottom-right corner, (0,0) + (800,600).
        #expect(Double(400) / 0.5 + 0 == 800)
        #expect(Double(300) / 0.5 + 0 == 600)
    }

    // MARK: - --scale

    @Test("--scale renders at exactly that multiplier, enlarging past the node's own size")
    func scaleEnlargesPastOwnSize() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("a-scaled.png").path
        // A is 160×120 — --scale 4 must enlarge it to 640×480, which --max never does.
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--scale", "4"
        )
        #expect(run.status == 0)
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("scale=4.0"))
        #expect(line.contains("pixels=640x480"))
        try #require(pixelSize(of: outputPath) == (640, 480))
    }

    @Test("--scale overrides --max rather than being capped by it")
    func scaleOverridesMax() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("a-scaled-max.png").path
        // --max 100 alone would shrink 160×120 well below its own size; --scale 4
        // still enlarges it to 640×480, so --scale is winning, not being capped.
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath,
            "--max", "100", "--scale", "4"
        )
        #expect(run.status == 0)
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("scale=4.0"))
        #expect(line.contains("pixels=640x480"))
    }

    @Test("--scale 1 behaves like the unscaled default")
    func scaleOneMatchesDefault() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("a-scale-one.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--scale", "1"
        )
        #expect(run.status == 0)
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("scale=1.0"))
        #expect(line.contains("pixels=160x120"))
    }

    @Test("--scale 0 is a usage error naming the flag, not a generic parse failure")
    func scaleZeroIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--scale", "0"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        // Asserting the specific remedy, not just "scale" (which an "Unknown option
        // --scale" parse failure would also contain before the flag exists) — this
        // is what actually tells the two failure modes apart.
        #expect(run.stderr.lowercased().contains("positive"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("A negative --scale is a usage error naming the flag, not a generic parse failure")
    func negativeScaleIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        // The `=` form, as TreeCommandTests.negativeDepthIsUsage does: a bare
        // "--scale" "-2" pair reads "-2" as an unrecognized flag, not a value —
        // ArgumentParser's own behavior, not something this flag can opt out of.
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--scale=-2"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.lowercased().contains("positive"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("--json reports the --scale value used")
    func jsonReportsScale() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("a-scaled.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--scale", "2", "--json"
        )
        #expect(run.status == 0)

        struct Decoded: Decodable { let scale: Double; let pixelWidth: Int }
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(run.stdout.utf8))
        #expect(decoded.scale == 2)
        #expect(decoded.pixelWidth == 320)
    }

    @Test("--json prints the same fields as structured data")
    func jsonMatchesTextFields() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("dashboard.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Dashboard", "--out", outputPath, "--json"
        )
        #expect(run.status == 0)

        struct Decoded: Decodable {
            struct Rect: Decodable { let x, y, width, height: Double }
            let node: String
            let scale: Double
            let rect: Rect
            let pixelWidth: Int
            let pixelHeight: Int
            let output: String
        }
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(run.stdout.utf8))
        #expect(decoded.node == "Dash1")
        #expect(decoded.scale == 1)
        #expect(decoded.rect.width == 800)
        #expect(decoded.pixelWidth == 800)
        #expect(decoded.output == outputPath)
    }

    // MARK: - Resolving a node inside a component instance

    @Test("A node inside a component instance resolves through the ref")
    func resolvesThroughARefInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("label.png").path

        // Nav01 is a ref to Btn01; Label (Lbl01) is one of Btn01's children, reached
        // only by stepping through the instance — see EditableDocument+Addressing.
        let run = try fixture.run(
            "shot", fixture.file.path, "Dashboard/Body/Nav/Label", "--out", outputPath, "--json"
        )
        #expect(run.status == 0)

        struct Decoded: Decodable { let node: String }
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(run.stdout.utf8))
        #expect(decoded.node == "Nav01/Lbl01")
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - --theme changes the rendered colors

    @Test("--theme changes the rendered colors on a themed fixture")
    func themeChangesColors() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let lightPath = fixture.root.appendingPathComponent("light.png").path
        let darkPath = fixture.root.appendingPathComponent("dark.png").path

        let light = try fixture.run(
            "shot", fixture.file.path, "container", "--out", lightPath, "--theme", "mode=light"
        )
        let dark = try fixture.run(
            "shot", fixture.file.path, "container", "--out", darkPath, "--theme", "mode=dark"
        )
        #expect(light.status == 0)
        #expect(dark.status == 0)

        let lightColor = try averageColor(of: lightPath)
        let darkColor = try averageColor(of: darkPath)
        // bgColor is #FFFFFF under mode=light and #1A1A1A under mode=dark — a large,
        // unmistakable difference if --theme actually reached the fill.
        let difference = abs(Int(lightColor.0) - Int(darkColor.0))
            + abs(Int(lightColor.1) - Int(darkColor.1))
            + abs(Int(lightColor.2) - Int(darkColor.2))
        #expect(difference > 200)
    }

    // MARK: - No node given

    @Test("No node given lists the top-level frames by name and id, and refuses")
    func noNodeListsTopLevelFrames() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run("shot", fixture.file.path, "--out", outputPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Dashboard"))
        #expect(run.stderr.contains("Dash1"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - An unresolvable address

    @Test("An address that does not resolve is a usage error")
    func unresolvableAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run("shot", fixture.file.path, "Nope", "--out", outputPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nope"))
    }

    // MARK: - A missing file

    @Test("A missing file is a target failure")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run(
            "shot", fixture.root.appendingPathComponent("nope.pen").path, "x", "--out", outputPath
        )

        #expect(run.status == ExitCode.targetFailure.rawValue)
    }

    // MARK: - Help

    @Test("--help routes a vision model's edge limit to --max and oversize to --crop")
    func helpNamesTheVisionModelBudget() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let run = try fixture.run("shot", "--help")
        #expect(run.status == 0, "\(run.stderr)")
        // ArgumentParser re-wraps the discussion to the terminal width, so a phrase can
        // straddle a line break; the assertion is about the words, not the layout.
        let help = run.stdout
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        #expect(help.contains("--max"))
        #expect(help.contains("--crop"))
        #expect(help.contains("vision model"))
        #expect(help.contains("pixels="))
    }

    // MARK: - --outline

    /// Criterion PqM. `shot-overlay.pen` puts rectangle `A` at exactly
    /// `(40, 40, 160, 120)` inside a 400×300 frame at the origin, so the box's pixels
    /// are arithmetic: the ring's inner band lands one pixel outside `rect × scale` on
    /// every side, whatever `--max` was. The scan lines are taken away from the top-left
    /// corner, where the label's tag sits.
    @Test("--outline draws the box on the node's layout rect at every --max")
    func outlineLandsOnTheNodeRectAtEveryMax() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        for (maxSize, scale) in [(400, 1.0), (200, 0.5)] {
            let outputPath = fixture.root.appendingPathComponent("outline-\(maxSize).png").path
            let run = try fixture.run(
                "shot", fixture.file.path, "Board", "--out", outputPath,
                "--max", "\(maxSize)", "--outline", "A"
            )
            #expect(run.status == 0)

            let image = try ShotImageProbe(contentsOf: outputPath)
            let left = Int(40 * scale), top = Int(40 * scale)
            let right = Int(200 * scale), bottom = Int(160 * scale)
            #expect(image.outlineInkColumns(inRow: (top + bottom) / 2) == [left - 1, right])
            #expect(image.outlineInkRows(inColumn: (left + right) / 2) == [top - 1, bottom])
        }
    }

    @Test("--outline is repeatable and each box lands on its own node")
    func outlineIsRepeatable() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("both.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--outline", "A", "--outline", "B"
        )
        #expect(run.status == 0)

        // A is (40,40,160,120); B is (240,180,120,80). At 1× the two boxes' vertical
        // bands sit at 39/200 and 239/360, and no row crosses both.
        let image = try ShotImageProbe(contentsOf: outputPath)
        #expect(image.outlineInkColumns(inRow: 100) == [39, 200])
        #expect(image.outlineInkColumns(inRow: 220) == [239, 360])
    }

    @Test("--outline resolves a node inside a component instance, like the target does")
    func outlineResolvesThroughARefInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("nav.png").path
        // Dash1 lays Header and Body out in a row, so Body starts at x=800 and the
        // instance inside it sits at a composed x of 850 — past Dashboard's own
        // 800-point width. Shoot Body, which does contain it. Shooting Dashboard put
        // the box at (0,0) and called it a pass, because the flag compared a
        // parent-relative rect against an absolute one; see ShotOutlineFrameTests.
        let run = try fixture.run(
            "shot", fixture.file.path, "Dashboard/Body", "--out", outputPath,
            "--outline", "Dashboard/Body/Nav/Label"
        )
        #expect(run.status == 0)
        #expect(FileManager.default.fileExists(atPath: outputPath))

        // Body's own origin is x=800, so Nav01/Lbl01 at 850 is 50 pixels in, 41 wide,
        // and the ring lands one pixel outside on each side. The rect starts at y=0,
        // leaving no room above it for the label's tag, so the tag sits inside the box
        // and rows 0–13 are its ink; row 16 crosses the ring and nothing else.
        let image = try ShotImageProbe(contentsOf: outputPath)
        #expect(image.outlineInkColumns(inRow: 16) == [49, 91])
    }

    @Test("An --outline address that does not resolve is a usage error naming it")
    func unresolvableOutlineIsUsage() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--outline", "Nope"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nope"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("An ambiguous --outline address is a usage error listing the candidates")
    func ambiguousOutlineListsCandidates() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        // Two nodes are named "Title": Ttl01 under Header and Ttl02 under Body.
        let run = try fixture.run(
            "shot", fixture.file.path, "Dashboard", "--out", outputPath, "--outline", "Title"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Ttl01"))
        #expect(run.stderr.contains("Ttl02"))
    }

    @Test("An --outline node outside the rendered node's rect is refused, not drawn nowhere")
    func outlineOutsideTheShotIsRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        // A is (40,40,160,120) and B is (240,180,120,80): shooting A, B is off-image.
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--outline", "B"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("B"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - --grid

    /// Criterion sbK, the arithmetic half: at a 2× ratio the ruler still counts in
    /// layout points, so a 400 pt-wide layout drawn 800 px wide reads 0, 100, 200, 300
    /// — not 0, 200, 400, 600 — and every tick sits at twice its own label.
    @Test("Grid ticks are layout points, not pixels, at a 2× ratio")
    func gridTicksAreLayoutPointsAtTwoTimes() {
        let layout = GridLayout(
            imageWidth: 800, imageHeight: 600, options: GridOptions(step: 100),
            pixelsPerPoint: 2
        )
        #expect(layout.columns.map(\.position) == [0, 100, 200, 300])
        #expect(layout.columns.map(\.pixelOffset) == [0, 200, 400, 600])
        #expect(layout.columns.map(\.label) == ["0", "100", "200", "300"])
        #expect(layout.rows.map(\.position) == [0, 100, 200])
    }

    /// Criterion sbK, the rendered half. `shot` never enlarges, so the only ratio a
    /// real run can reach other than 1 is a shrink: 400 pt at `--max 200` is 0.5, and
    /// the ruler must still read 0, 100, 200, 300 — half as many pixels apart, the
    /// same numbers.
    @Test("--grid grows the image by exactly the gutters GridLayout predicts")
    func gridGrowsTheImageByThePredictedGutters() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("grid.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--max", "200", "--grid",
            "--json"
        )
        #expect(run.status == 0)

        let decoded = try JSONDecoder().decode(GridShot.self, from: Data(run.stdout.utf8))
        let predicted = GridLayout(
            imageWidth: 200, imageHeight: 150, options: GridOptions(), pixelsPerPoint: 0.5
        )
        #expect(decoded.scale == 0.5)
        #expect(decoded.gutterLeft == predicted.leftGutter)
        #expect(decoded.gutterTop == predicted.topGutter)
        #expect(decoded.pixelWidth == predicted.width)
        #expect(decoded.pixelHeight == predicted.height)
        // The gridded image exceeds --max by its gutter, by design.
        #expect(decoded.pixelWidth > 200)

        let image = try ShotImageProbe(contentsOf: outputPath)
        #expect(image.width == predicted.width)
        #expect(image.height == predicted.height)
        // The ruler counts in layout points: 400 pt across 200 px still ticks at 300.
        #expect(predicted.columns.map(\.position) == [0, 100, 200, 300])
    }

    @Test("--grid on a nested node numbers the ruler from that node's own origin")
    func gridNumbersFromTheRenderedNodesOrigin() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("grid-a.png").path
        // A's layout rect starts at (40, 40), so the first tick a 100 pt step can show
        // is 100 — the ruler reads the document's coordinates, not the crop's.
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--grid", "--json"
        )
        #expect(run.status == 0)

        let decoded = try JSONDecoder().decode(GridShot.self, from: Data(run.stdout.utf8))
        let predicted = GridLayout(
            imageWidth: 160, imageHeight: 120, options: GridOptions(),
            pixelsPerPoint: 1, origin: CGPoint(x: 40, y: 40)
        )
        #expect(predicted.columns.map(\.position) == [100])
        #expect(decoded.pixelWidth == predicted.width)
        #expect(decoded.pixelHeight == predicted.height)
    }

    @Test("Without --grid the gutters are zero, so the mapping formula still holds")
    func gutterIsZeroWithoutGrid() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("plain.png").path
        let run = try fixture.run("shot", fixture.file.path, "Board", "--out", outputPath)
        #expect(run.status == 0)
        #expect(try #require(run.stdoutLines.first).contains("gutter=0,0"))
    }

    /// The fields `--grid` adds, decoded from `--json`.
    private struct GridShot: Decodable {
        let scale: Double
        let pixelWidth: Int
        let pixelHeight: Int
        let gutterLeft: Int
        let gutterTop: Int
    }

    // MARK: - --extent painted rounds to whole pixels the way Pen's export does

    /// Pen's PNG export grows a painted extent's pixel size up to the next whole pixel
    /// at the render scale, keeping the extent's own — possibly fractional — corner
    /// (``Woodcase/PenRect/grownToWholePixels(at:)``,
    /// `project/2026-09-28-geometry-model.md` § 5). `geometry-probe.pen`'s x1–x4, free
    /// and groups boards are the same six probes `PenPaintedExtentProbeTests` holds to
    /// Pen's own 2x exports (`scripts/pen-oracle geometry-probe.pen --scale 2`); this
    /// reads the same numbers off the built binary rather than the library function.
    private static let paintedExports: [(board: String, width: Int, height: Int)] = [
        ("x1", 296, 216), ("x2", 299, 270), ("x3", 260, 180), ("x4", 224, 144),
        ("free", 1488, 803), ("groups", 1440, 733),
    ]

    @Test("--extent painted's pixel size at 2x matches Pen's own export", arguments: paintedExports)
    func extentPaintedMatchesPensExportPixelSize(board: String, width: Int, height: Int) throws {
        let fixture = try CommandFixture(fixture: "geometry-probe.pen")
        try fixture.seedFontCache(family: "Inter", files: Self.interFiles)
        let outputPath = fixture.root.appendingPathComponent("\(board).png").path
        let run = try fixture.run(
            "shot", fixture.file.path, board, "--out", outputPath,
            "--extent", "painted", "--scale", "2", "--json"
        )
        #expect(run.status == 0)
        let decoded = try JSONDecoder().decode(PaintedShot.self, from: Data(run.stdout.utf8))
        #expect(decoded.pixelWidth == width, "\(board): \(decoded)")
        #expect(decoded.pixelHeight == height, "\(board): \(decoded)")
        try #require(pixelSize(of: outputPath) == (width, height))
    }

    /// Pen keeps the extent's exact corner and rounds only the pixel *size* up — it does
    /// not snap the origin to a pixel (`grownToWholePixels(at:)`'s doc comment). x2's
    /// painted extent turns 30°, so its corner is fractional in both axes; growing it to
    /// whole pixels must not round that away.
    @Test("--extent painted keeps the extent's fractional corner; only the pixel size grows")
    func extentPaintedKeepsFractionalOrigin() throws {
        let fixture = try CommandFixture(fixture: "geometry-probe.pen")
        try fixture.seedFontCache(family: "Inter", files: Self.interFiles)
        let outputPath = fixture.root.appendingPathComponent("x2.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "x2", "--out", outputPath,
            "--extent", "painted", "--scale", "2", "--json"
        )
        #expect(run.status == 0)
        let decoded = try JSONDecoder().decode(PaintedShot.self, from: Data(run.stdout.utf8))
        let s30 = 0.5, c30 = cos(Double.pi / 6)
        let x = 2400 - 12 * c30 - 12 * s30
        let y = 900 - 112 * s30 - 12 * c30
        #expect(abs(decoded.rect.x - x) < 1e-6, "\(decoded)")
        #expect(abs(decoded.rect.y - y) < 1e-6, "\(decoded)")
    }

    /// The committed variable-font file `geometry-probe.pen`'s text board names as
    /// `fontFamily: "Inter"`, seeded into the fixture's own font cache
    /// (``CommandFixture/seedFontCache(family:files:)``) so a `shot` of it never
    /// downloads — `CommandFixtureFontsTests` requires this of every fixture a network
    /// verb loads that names a font family.
    private static let interFiles = ["Inter[opsz,wght].ttf"]

    /// The fields decoded from a `--extent painted --json` run.
    private struct PaintedShot: Decodable, CustomStringConvertible {
        let scale: Double
        let rect: PenRect
        let pixelWidth: Int
        let pixelHeight: Int

        var description: String {
            "scale=\(scale) rect=\(rect) pixels=\(pixelWidth)x\(pixelHeight)"
        }
    }

    // MARK: - Helpers

    /// Reads a PNG's pixel dimensions.
    private func pixelSize(of path: String) throws -> (width: Int, height: Int) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    /// Downsamples a PNG to a single pixel to get its dominant color, so a solid
    /// background fill dominates regardless of foreground text.
    private func averageColor(of path: String) throws -> (UInt8, UInt8, UInt8) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }
}
