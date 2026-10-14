//
//  ShotSVGCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `shot --svg` writes the node as an SVG instead of a PNG, framed the way the PNG is.
@Suite("shot --svg")
struct ShotSVGCommandTests {
    @Test("--svg writes an SVG of the node, framed by the printed rect, at 1 point per unit")
    func writesSVG() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("board.svg").path
        let run = try fixture.run("shot", fixture.file.path, "Board", "--out", outputPath, "--svg")
        #expect(run.status == 0, "\(run.stderr)")
        let line = try #require(run.stdoutLines.first)
        #expect(line.contains("scale=1.0"))
        #expect(line.contains("rect=0.0,0.0,400.0,300.0"))
        #expect(line.contains("pixels=400x300"))

        let xml = try XMLDocument(contentsOf: URL(fileURLWithPath: outputPath))
        let root = try #require(xml.rootElement())
        #expect(root.name == "svg")
        #expect(root.attribute(forName: "viewBox")?.stringValue == "0 0 400 300")
        let fills = try xml.nodes(forXPath: "//*[local-name()='path']/@fill").compactMap(\.stringValue)
        #expect(fills == ["#f0f0f0", "#e23b3b", "#3b6fe2"])
    }

    @Test("--svg of a nested node frames it in its parent's space, as the PNG does")
    func nestedNode() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("a.svg").path
        let run = try fixture.run("shot", fixture.file.path, "Board/A", "--out", outputPath, "--svg")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try #require(run.stdoutLines.first).contains("rect=40.0,40.0,160.0,120.0"))
        let xml = try XMLDocument(contentsOf: URL(fileURLWithPath: outputPath))
        #expect(xml.rootElement()?.attribute(forName: "viewBox")?.stringValue == "40 40 160 120")
    }

    @Test("--svg with --grid, --outline or --scale is refused: those are raster-only")
    func rasterOnlyFlagsAreRefused() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("refused.svg").path
        for extra in [["--grid"], ["--outline", "Board/A"], ["--scale", "2"]] {
            let run = try fixture.run(["shot", fixture.file.path, "Board", "--out", outputPath, "--svg"] + extra)
            #expect(run.status == ExitCode.usage.rawValue, "\(extra)")
            #expect(run.stderr.contains("--svg"), "\(extra): \(run.stderr)")
            #expect(!FileManager.default.fileExists(atPath: outputPath))
        }
    }
}
