//
//  ShotCropTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WoodcaseCommandCore

/// `shot --crop x,y,w,h` renders a sub-rectangle of the node, in the node's own
/// coordinate space.
///
/// A tall board shrunk whole to a vision model's edge limit is unreadable; the answer
/// is to tile it, and a tile is a crop. So `--max` and `--scale` measure the *crop*,
/// the printed `rect=` is the crop — which keeps `point = (pixel − gutter) / scale +
/// origin` true without a second formula — and `--outline` is judged against the crop
/// rather than the whole node.
@Suite("shot --crop")
struct ShotCropTests {
    // MARK: - Geometry

    @Test("A crop renders exactly its own rectangle and reports it as the origin")
    func cropRendersItsOwnRectangle() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("crop.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--crop", "100,50,200,150"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("rect=100.0,50.0,200.0,150.0"))
        #expect(line.contains("pixels=200x150"))
        #expect(line.contains("scale=1.0"))
        #expect(try pixelSize(of: outputPath) == (200, 150))
    }

    @Test("--max sizes the crop, not the whole node, so a tile renders legibly")
    func maxAppliesToTheCropsOwnSize() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        // Board is 400×300: --max 100 on the whole node would be scale 0.25. The same
        // --max on a 200×150 crop is 0.5, which is the point of tiling.
        let cropped = fixture.root.appendingPathComponent("tile.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", cropped,
            "--crop", "0,0,200,150", "--max", "100"
        )
        #expect(run.status == 0, "\(run.stderr)")
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("scale=0.5"))
        #expect(line.contains("pixels=100x75"))
        #expect(try pixelSize(of: cropped) == (100, 75))

        let whole = fixture.root.appendingPathComponent("whole.png").path
        let full = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", whole, "--max", "100"
        )
        #expect(try #require(full.stdoutLines.first).contains("scale=0.25"))
    }

    @Test("--scale enlarges the crop, not the node")
    func scaleAppliesToTheCropsOwnSize() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("zoom.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--crop", "40,40,80,60", "--scale", "4"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try #require(run.stdoutLines.first).contains("pixels=320x240"))
        #expect(try pixelSize(of: outputPath) == (320, 240))
    }

    @Test("--json reports the crop as the origin and the node's own rect alongside it")
    func jsonSeparatesTheCropFromTheNodesRect() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("crop.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--crop", "100,50,200,150", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let decoded = try JSONDecoder().decode(
            ShotRectsTests.RectsShot.self, from: Data(run.stdout.utf8)
        )
        #expect([decoded.rect.x, decoded.rect.y] == [100, 50])
        #expect([decoded.rect.width, decoded.rect.height] == [200, 150])
        let node = try #require(decoded.rects.first)
        #expect(node.id == "Brd01")
        #expect([node.rect.x, node.rect.y, node.rect.width, node.rect.height] == [0, 0, 400, 300])
    }

    @Test("A crop of a node away from the origin is written in that node's own space")
    func cropOfANodeAwayFromTheOrigin() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        // A's own rect is (40,40,160,120), so its top-left corner is 40,40 and not 0,0
        // — the crop is in the same space the printed rect= uses, not an offset from
        // the node's corner.
        let outputPath = fixture.root.appendingPathComponent("a-crop.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "A", "--out", outputPath, "--crop", "60,60,80,60"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try #require(run.stdoutLines.first).contains("rect=60.0,60.0,80.0,60.0"))
        #expect(try pixelSize(of: outputPath) == (80, 60))

        // The same numbers read as an offset from A's corner would be inside it; read
        // in A's own space they start off its left edge, and are refused.
        let offsetPath = fixture.root.appendingPathComponent("a-offset.png").path
        let offset = try fixture.run(
            "shot", fixture.file.path, "A", "--out", offsetPath, "--crop", "0,0,80,60"
        )
        #expect(offset.status == ExitCode.usage.rawValue)
        #expect(offset.stderr.contains("40.0,40.0,160.0,120.0"))
        #expect(!FileManager.default.fileExists(atPath: offsetPath))
    }

    // MARK: - Refusals

    @Test("A crop that runs off the node is refused, naming the rect and the crop that fits")
    func cropOutsideTheNodeIsRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("over.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--crop", "300,0,200,100"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("0.0,0.0,400.0,300.0"))
        #expect(run.stderr.contains("--crop 300.0,0.0,100.0,100.0"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("A crop that is not four numbers is refused before anything is rendered")
    func malformedCropIsRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("bad.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--crop", "1,2,3"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("x,y,w,h"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("A crop with no area is refused")
    func emptyCropIsRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("empty.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--crop", "0,0,0,100"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.lowercased().contains("positive"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - --outline is judged against the crop

    @Test("An --outline inside the node but off the crop is refused, pointing at --crop")
    func outlineOffTheCropIsRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("offcrop.png").path
        // B is at (240,180); the crop stops at (200,150).
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--crop", "0,0,200,150", "--outline", "B"
        )
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("B"))
        #expect(run.stderr.contains("--crop"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("An --outline that overlaps the crop is drawn")
    func outlineOverlappingTheCropIsDrawn() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("oncrop.png").path
        // A is at (40,40,160,120) — it overlaps the crop even though it overhangs it.
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--crop", "0,0,200,150", "--outline", "A", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let decoded = try JSONDecoder().decode(
            ShotRectsTests.RectsShot.self, from: Data(run.stdout.utf8)
        )
        #expect(decoded.rects.map(\.role) == ["node", "outline"])
        #expect(try #require(decoded.rects.last).id == "RctA1")
    }

    // MARK: - Helpers

    /// Reads a PNG's pixel dimensions.
    ///
    /// - Parameter path: The file to measure.
    /// - Returns: Its width and height in pixels.
    /// - Throws: When the file cannot be read or decoded.
    private func pixelSize(of path: String) throws -> (width: Int, height: Int) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }
}
