//
//  ShotOutlineFrameTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `--outline` on a node that is not a direct child of the node being shot.
///
/// ``PenLayoutEngine`` settles every rect **relative to its parent**, and only a
/// top-level node's rect is in canvas coordinates. `--outline` used to read one rect
/// straight out of that map and treat it as absolute, which is right for a direct child
/// of an artboard at the origin — every fixture the flag was built against — and wrong
/// everywhere else: a box four levels down landed at its offset from its own parent,
/// and an artboard placed away from the origin refused its own descendants as "outside
/// the rendered node".
@Suite("shot --outline coordinate frame")
struct ShotOutlineFrameTests {
    @Test("A box four levels down lands on the node's composed position, not its parent offset")
    func deepBoxLandsOnItsComposedPosition() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let outputPath = fixture.root.appendingPathComponent("deep.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "layout-deep-nesting", "--out", outputPath,
            "--outline", "deep-leaf-2"
        )
        #expect(run.status == 0, "\(run.stderr)")

        // layout-deep-nesting.layout.json is the settled, parent-relative truth:
        // Ms0rE(0,0) → S4auN(10,10) → o3V8H(193,8) → D48Fa(6,6) → YOoQM(34,0), a
        // 30×20 rectangle. Composed, that is (243, 24) — while the rect the engine
        // stores for YOoQM alone reads (34, 0).
        let image = try ShotImageProbe(contentsOf: outputPath)
        #expect(image.outlineInkColumns(inRow: 34) == [242, 273])
        // On a rect this narrow the label's tag sits above the box and inks rows of
        // its own, so the ring is the last pair.
        #expect(Array(image.outlineInkRows(inColumn: 258).suffix(2)) == [23, 44])
    }

    @Test("An outline outside the rendered node's subtree is refused, naming it")
    func outlineOutsideTheSubtreeIsRefused() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let outputPath = fixture.root.appendingPathComponent("out.png").path
        // level-3a and level-3b are siblings: neither contains the other's leaves.
        let run = try fixture.run(
            "shot", fixture.file.path, "level-3a", "--out", outputPath,
            "--outline", "deep-leaf-2"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("deep-leaf-2"))
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }
}
