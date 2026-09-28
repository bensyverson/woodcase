//
//  TreeAbsoluteCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase tree --absolute`, and the `absRect` every `--json` row carries.
///
/// The coordinate convention is the one thing about `tree` an agent cannot guess: a
/// nested row's `x,y` is an offset inside its own parent, so a leaf in a laid-out
/// stack reads `0,0` and looks, to a reader who has not been told, like a bug. The
/// flag and the JSON key make the other frame available without a parent walk, and the
/// help says which is which.
@Suite("woodcase tree --absolute")
struct TreeAbsoluteCommandTests {
    /// Ms0rE(0,0) → S4auN(10,10) → o3V8H(193,8) → D48Fa(6,6) → gaLFu(0,0), from
    /// `layout-deep-nesting.layout.json`.
    static let deepLeafAbsolute = PenRect(x: 209, y: 24, width: 30, height: 20)

    @Test("Without the flag a nested rect is its offset inside its own parent")
    func defaultRectsAreParentRelative() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        let leaf = try #require(run.stdoutLines.first { $0.hasSuffix("gaLFu") })
        #expect(leaf.contains("0,0 30×20"))
    }

    @Test("--absolute prints the same rect in document space")
    func absoluteRectsAreDocumentSpace() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let run = try fixture.run("tree", fixture.file.path, "--absolute")

        #expect(run.status == 0)
        let leaf = try #require(run.stdoutLines.first { $0.hasSuffix("gaLFu") })
        #expect(leaf.contains("209,24 30×20"))
    }

    @Test("The header says the listing is absolute, so a saved outline is unambiguous")
    func headerNamesTheCoordinateSystem() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")

        let relative = try fixture.run("tree", fixture.file.path)
        let absolute = try fixture.run("tree", fixture.file.path, "--absolute")

        #expect(!relative.stdoutLines[0].contains("absolute"))
        #expect(absolute.stdoutLines[0].hasSuffix("  absolute"))
    }

    @Test("--json rows carry both rects, with no flag needed")
    func jsonRowsCarryBothRects() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let leaf = try #require(report.rows.first { $0.id == "gaLFu" })
        #expect(leaf.rect == PenRect(x: 0, y: 0, width: 30, height: 20))
        #expect(leaf.absRect == Self.deepLeafAbsolute)
    }

    @Test("A --json row's absRect is the rect shot reports for the same node")
    func absRectAgreesWithShot() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let tree = try fixture.run("tree", fixture.file.path, "--json")
        let shot = try fixture.run(
            "shot", fixture.file.path, "layout-deep-nesting",
            "--out", fixture.root.appendingPathComponent("shot.png").path
        )

        #expect(shot.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8))
        let root = try #require(report.rows.first { $0.id == "Ms0rE" })

        // `shot` prints `rect=x,y,w,h` for the node it drew, in the frame the layout
        // engine computed it in — which for a top-level node is document space.
        let field = try #require(
            shot.stdout.split(separator: " ").first { $0.hasPrefix("rect=") }
        )
        let numbers = field.dropFirst("rect=".count).split(separator: ",").compactMap { Double($0) }
        #expect(numbers.count == 4)
        #expect(root.absRect == PenRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
    }

    @Test("The help states the convention and where the other frame is")
    func helpTeachesTheConvention() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("parent-relative"))
        #expect(run.stdout.contains("--absolute"))
        #expect(run.stdout.contains("absRect"))
    }
}
