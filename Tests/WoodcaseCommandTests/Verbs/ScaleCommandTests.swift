//
//  ScaleCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase scale`: an adapter over ``EditPlanner/planScale(nodeIDs:by:anchor:in:layout:)``,
/// so what matters here is that it reaches the planner, reads the factor and the anchor,
/// writes one transaction and reports the result.
@Suite("woodcase scale")
struct ScaleCommandTests {
    @Test("A percentage scales a frame and its children about the anchor, and one undo takes it back")
    func scaleThenUndo() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "scale", fixture.file.path, "Canvas", "--by", "150%", "--anchor", "center", "--as", "ana", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        #expect((report?["operations"] as? Int ?? 0) > 0)
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        #expect(document.node(id: "Cnv01").flatMap { try? NodePropertyCodec.value(at: "kind.width", of: $0) } == 600)
        #expect(document.node(id: "Cnv01")?.common.x == .literal(-100))
        #expect(document.node(id: "Cd101").flatMap { try? NodePropertyCodec.value(at: "kind.width", of: $0) } == 150)

        let undone = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undone.status == 0, "\(undone.stderr)")
        let restored = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        let original = try EditableDocument(from: PenParser.parse(before))
        #expect(restored.node(id: "Cnv01") == original.node(id: "Cnv01"))
    }

    @Test("A factor that is not a positive number is a usage failure that writes nothing", arguments: ["0", "-2", "big", "0%"])
    func badFactor(factor: String) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("scale", fixture.file.path, "Canvas", "--by", factor, "--as", "ana")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("is not a factor"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("An unknown anchor is a usage failure that names the nine")
    func badAnchor() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("scale", fixture.file.path, "Canvas", "--by", "2", "--anchor", "middle", "--as", "ana")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("bottom-right"))
    }
}
