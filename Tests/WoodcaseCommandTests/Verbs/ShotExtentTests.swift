//
//  ShotExtentTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `shot --extent painted` frames what the node paints — its stroke band, shadow and
/// unclipped children — instead of its layout rect, the way Pen frames an export.
///
/// `shot-painted-extent.pen`: `Card` is 100×60 at (40, 30) with a 12 pt outer stroke and
/// a shadow offset (10, 10), blur 8 — painted 148×108 from (26, 16). `Board` is 200×100
/// at (300, 0), unclipped, with a child reaching 20 pt right of it and 10 pt above it.
@Suite("shot --extent")
struct ShotExtentTests {
    @Test("By default a shot frames the layout rect")
    func defaultIsLayout() throws {
        let fixture = try CommandFixture(fixture: "shot-painted-extent.pen")
        let path = fixture.root.appendingPathComponent("card.png").path
        let run = try fixture.run("shot", fixture.file.path, "Card", "--out", path)
        #expect(run.status == 0, "\(run.stderr)")
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("rect=40.0,30.0,100.0,60.0"), "\(line)")
        #expect(line.contains("pixels=100x60"), "\(line)")
        let explicit = try fixture.run("shot", fixture.file.path, "Card", "--out", path, "--extent", "layout")
        #expect(explicit.stdoutLines.first == line)
    }

    @Test("--extent painted frames the stroke band and the shadow")
    func paintedFramesStrokeAndShadow() throws {
        let fixture = try CommandFixture(fixture: "shot-painted-extent.pen")
        let path = fixture.root.appendingPathComponent("card.png").path
        let run = try fixture.run("shot", fixture.file.path, "Card", "--out", path, "--extent", "painted")
        #expect(run.status == 0, "\(run.stderr)")
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("rect=26.0,16.0,148.0,108.0"), "\(line)")
        #expect(line.contains("pixels=148x108"), "\(line)")
        let image = try ShotImageProbe(contentsOf: path)
        #expect(image.width == 148 && image.height == 108)
        // The stroke's outer edge is on the image: 6 px in from the left, halfway down,
        // is green band, not background.
        let band = try #require(image.color(x: 6, y: 54))
        #expect(band.green > 100 && band.red < 60, "\(band)")
    }

    @Test("--extent painted reaches an unclipped frame's overhanging child; a crop may start in the overhang")
    func paintedReachesChildren() throws {
        let fixture = try CommandFixture(fixture: "shot-painted-extent.pen")
        let path = fixture.root.appendingPathComponent("board.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", path, "--extent", "painted", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("\"height\" : 110"), "\(run.stdout)")
        #expect(run.stdout.contains("\"width\" : 220"), "\(run.stdout)")
        #expect(run.stdout.contains("\"y\" : -10"), "\(run.stdout)")

        let crop = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", path, "--extent", "painted", "--crop", "480,-10,40,20"
        )
        #expect(crop.status == 0, "\(crop.stderr)")
        #expect(try #require(crop.stdoutLines.first).contains("rect=480.0,-10.0,40.0,20.0"))
    }

    @Test("An unknown --extent is a usage error naming both choices")
    func unknownExtent() throws {
        let fixture = try CommandFixture(fixture: "shot-painted-extent.pen")
        let path = fixture.root.appendingPathComponent("card.png").path
        let run = try fixture.run("shot", fixture.file.path, "Card", "--out", path, "--extent", "ink")
        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("layout") && run.stderr.contains("painted"), "\(run.stderr)")
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
