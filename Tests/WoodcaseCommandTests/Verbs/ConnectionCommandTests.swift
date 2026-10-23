//
//  ConnectionCommandTests.swift
//  WoodcaseCommandTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The CLI shows and draws connections (c41x gaps 3–5): `tree` and `find` rows name a
/// connection's two ends, `add` writes no artboard position on one, and `shot` and `render`
/// of a frame draw the connections whose ends fall inside it.
///
/// `connectors-routes.pen`: a `Board` frame at (0,0) 640×420 holding `Start`, `Ahead`,
/// `Below`, `Behind` and `Card` (with `Dot` inside), and four top-level connections.
@Suite("Connections in the CLI")
struct ConnectionCommandTests {
    @Test("A connection's tree row names its two ends")
    func treeShowsEnds() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        let row = try #require(run.stdoutLines.first { $0.hasSuffix(" Step") })
        #expect(row.contains("[Start.bottom → Below.left]"), "the row reads \(row)")
    }

    @Test("tree --json carries each end's path, anchor and name")
    func treeJSONCarriesEnds() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let step = try #require(report.rows.first { $0.id == "Step" })
        let connection = try #require(step.connection)
        #expect(connection.source == TreeRow.Connection.End(path: "Start", anchor: "bottom", name: "Start"))
        #expect(connection.target == TreeRow.Connection.End(path: "Below", anchor: "left", name: "Below"))
        #expect(report.rows.first { $0.id == "Board" }?.connection == nil)
    }

    @Test("find reads a connection's ends")
    func findReadsEnds() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let run = try fixture.run(
            "find", fixture.file.path, #"r => r.connection && r.connection.target.path === "Dot""#
        )

        #expect(run.status == 0, "find failed: \(run.stderr)")
        let rows = run.stdoutLines.filter { $0.hasSuffix(" Nested") }
        #expect(rows.count == 1, "\(run.stdout)")
        #expect(rows.first?.contains("[Below.right → Dot.top]") == true)
    }

    @Test("add of a top-level connection writes no artboard position")
    func addPlacesNoConnection() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let file = fixture.root.appendingPathComponent("link.json")
        try #"""
        {"type":"connection","name":"Link","source":{"path":"Ahead","anchor":"bottom"},
         "target":{"path":"Below","anchor":"top"},"stroke":"#000000"}
        """#.write(to: file, atomically: true, encoding: .utf8)

        let run = try fixture.run("add", fixture.file.path, "document", "-F", file.path)

        #expect(run.status == 0, "add failed: \(run.stderr)")
        #expect(!run.stdout.contains("clear of the artboards"), "\(run.stdout)")
        #expect(!run.stderr.contains("clear of the artboards"), "\(run.stderr)")
        let link = try #require(PenFileProbe(fixture.file).root(named: "Link"))
        #expect(link.common.x == nil && link.common.y == nil)
    }

    @Test("shot of a frame draws the connections whose ends are inside it")
    func shotDrawsConnections() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let out = fixture.root.appendingPathComponent("board.png").path
        let run = try fixture.run("shot", fixture.file.path, "Board", "--out", out, "--scale", "1")

        #expect(run.status == 0, "shot failed: \(run.stderr)")
        // Plain runs from Start's right (160,70) to Ahead's left (260,70), #18181B.
        let pixel = try Self.pixel(at: 210, 70, in: out)
        #expect(pixel.red < 60 && pixel.green < 60 && pixel.blue < 60, "\(pixel)")
    }

    @Test("render of a frame draws the connections whose ends are inside it")
    func renderDrawsConnections() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let run = try fixture.run("render", fixture.file.path, "--scale", "1")

        #expect(run.status == 0, "render failed: \(run.stderr)")
        let png = fixture.root.appendingPathComponent("connectors-routes.png").path
        // Step's elbow runs down from Start's bottom (100,100) to y 210: at (100,150), #2563EB.
        let pixel = try Self.pixel(at: 100, 150, in: png)
        #expect(pixel.blue > 200 && pixel.red < 80, "\(pixel)")
    }

    // MARK: - Pixels

    /// One pixel's channels, read from a PNG at a pixel coordinate.
    private static func pixel(at x: Int, _ y: Int, in path: String) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (pixel[0], pixel[1], pixel[2])
    }
}
