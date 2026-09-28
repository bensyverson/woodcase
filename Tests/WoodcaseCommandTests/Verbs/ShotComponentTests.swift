//
//  ShotComponentTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `shot` over the two shapes a real Pen document puts at the top level: a reusable
/// component *definition*, and a `ref` that *places* one on the canvas.
///
/// Neither used to render. Ref expansion re-ids an instance root to
/// `<refID>/<component root id>` and drops definitions altogether, so the authored id
/// `shot` looked up in the layout rects was never there — every top-level frame failed
/// with "has no computed layout rect" and exit 5.
///
/// These tests are about addressing, not typography, so the fixture
/// (`shot-component-addressing.pen`) is purpose-built and names no `fontFamily` at all —
/// every text node falls back to `PenTextMeasurer.defaultFontFamily`, resolved from the
/// system font list alone. An earlier version of this file shot `banking.pen` and
/// `woodcase-app.pen`, whose text nodes name "Inter" and "$font-primary" (IBM Plex
/// Sans); neither is preinstalled, and `CommandFixture`'s subprocess gets a fresh, empty
/// `$WOODCASE_HOME` with none of the test target's own font registration or cache, so
/// every run of those six tests downloaded a font from GitHub (issue `e2iLwV`).
@Suite("shot over components")
struct ShotComponentTests {
    // MARK: - A reusable definition

    @Test("A top-level reusable component definition renders as itself")
    func definitionRendersAsItself() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("card.png").path
        // kD4nP "card" is `reusable: true` — a definition, which expansion strips
        // unless it is asked to keep them.
        let run = try fixture.run(
            "shot", fixture.file.path, "card", "--out", outputPath, "--json"
        )

        #expect(run.status == 0, "\(run.stderr)")
        let shot = try Self.decode(run.stdout)
        #expect(shot.node == "kD4nP")
        #expect(shot.rect.width > 0)
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("A node inside a reusable definition renders under its own id")
    func descendantOfADefinitionRenders() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("label.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "card/label", "--out", outputPath, "--json"
        )

        #expect(run.status == 0, "\(run.stderr)")
        // A definition's children keep their authored ids: nothing prefixes them.
        #expect(try Self.decode(run.stdout).node == "aRj2Q")
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - A placed instance

    @Test("A top-level component instance renders under the id expansion gives it")
    func instanceRendersUnderItsExpandedID() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("card-light.png").path
        // wZ8Lk is a ref to kD4nP, so the expanded instance root is `wZ8Lk/kD4nP`.
        let run = try fixture.run(
            "shot", fixture.file.path, "Card (Light)", "--out", outputPath, "--json"
        )

        #expect(run.status == 0, "\(run.stderr)")
        let shot = try Self.decode(run.stdout)
        #expect(shot.node == "wZ8Lk/kD4nP")
        #expect(shot.rect.width > 0)
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("A node inside a placed instance renders under its prefixed id")
    func descendantOfAnInstanceRenders() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("card-light-label.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Card (Light)/label",
            "--out", outputPath, "--json"
        )

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.decode(run.stdout).node == "wZ8Lk/aRj2Q")
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("--outline boxes a node inside a placed instance")
    func outlineInsideAnInstance() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let outputPath = fixture.root.appendingPathComponent("outlined.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Card (Light)", "--out", outputPath,
            "--outline", "Card (Light)/label", "--json"
        )

        #expect(run.status == 0, "\(run.stderr)")
        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    // MARK: - The refusal lists only what it can render

    @Test("No node given lists definitions and instances, and every id it names renders")
    func noNodeListsEveryRenderableTopLevelNode() throws {
        let fixture = try CommandFixture(fixture: "shot-component-addressing.pen")
        let refused = try fixture.run(
            "shot", fixture.file.path,
            "--out", fixture.root.appendingPathComponent("none.png").path
        )

        #expect(refused.status == ExitCode.usage.rawValue)
        // The definition...
        #expect(refused.stderr.contains("kD4nP"))
        #expect(refused.stderr.contains("card"))
        // ...and the refs that place it, which are this file's real artboards.
        #expect(refused.stderr.contains("wZ8Lk"))
        #expect(refused.stderr.contains("vN3Ts"))

        // The list is honest: an id read straight off it renders.
        let outputPath = fixture.root.appendingPathComponent("light.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "wZ8Lk", "--out", outputPath, "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.decode(run.stdout).node == "wZ8Lk/kD4nP")
    }

    // MARK: - A rect that is genuinely missing

    @Test("A missing layout rect is a usage failure naming the address, never exit 5")
    func missingRectIsUsageNotEnvironment() {
        let failure = ShotTargets.missingRectFailure(
            address: "Nav01/Lbl01",
            requested: "Dashboard/Body/Nav/Label",
            editing: URL(fileURLWithPath: "/tmp/design.pen")
        )

        #expect(failure.exitCode == ExitCode.usage)
        #expect(failure.exitCode != ExitCode.environment)
        #expect(failure.message.contains("Nav01/Lbl01"))
        #expect(failure.message.contains("Dashboard/Body/Nav/Label"))
        // An error that teaches names the next command.
        #expect(failure.message.contains("woodcase tree"))
    }

    // MARK: - Helpers

    /// The `--json` fields these tests read.
    private struct Decoded: Decodable {
        /// The rendered node's id, as the layout engine spells it.
        let node: String

        /// The node's settled layout rect.
        let rect: Rect

        /// A layout rect, in points.
        struct Rect: Decodable {
            /// The rect's width.
            let width: Double
        }
    }

    /// Decodes one `--json` line.
    ///
    /// - Parameter stdout: What the run printed.
    /// - Returns: The decoded fields.
    /// - Throws: Whatever `JSONDecoder` throws for output that is not the report.
    private static func decode(_ stdout: String) throws -> Decoded {
        try JSONDecoder().decode(Decoded.self, from: Data(stdout.utf8))
    }
}
