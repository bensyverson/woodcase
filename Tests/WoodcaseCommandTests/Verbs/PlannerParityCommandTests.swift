//
//  PlannerParityCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase set` and `woodcase override` write exactly what an editor's
/// ``EditPlanner`` plan writes for the same intent, and refuse what it refuses.
@Suite("The CLI's set and override match the edit planner")
struct PlannerParityCommandTests {
    /// The fixture as an editor holds it, after applying a plan for `intent`.
    private func editorResult(_ intent: EditIntent, at raw: String) throws -> PenDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WoodcaseTests/Fixtures/planner.pen")
        let document = try EditableDocument(from: PenParser.parse(contentsOf: url))
        let plan = try EditPlanner.plan(intent, at: #require(NodeAddress(raw)), in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
        return document.materialize()
    }

    /// The file the CLI wrote, parsed.
    private func written(_ fixture: CommandFixture) throws -> PenDocument {
        try PenParser.parse(contentsOf: fixture.file)
    }

    @Test("set on a plain node writes what the planner's set writes")
    func setOnNode() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let run = try fixture.run("set", fixture.file.path, "Board/Free", "common.opacity=0.5", "--as", "t")

        #expect(run.status == 0)
        #expect(try written(fixture) == editorResult(.set(["common.opacity": 0.5]), at: "Board/Free"))
    }

    @Test("set inside an instance is refused, as the planner refuses it, naming the override to run")
    func setInsideInstance() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let before = try written(fixture)
        let run = try fixture.run("set", fixture.file.path, "Board/Chip/Label", "kind.content=Go", "--as", "t")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase override \(fixture.file.path) 'Board/Chip/Label' 'content=Go'"),
                "\(run.stderr)")
        #expect(try written(fixture) == before)
    }

    @Test("override writes what the planner's override writes for the same descendant")
    func overrideMatchesEditorOverride() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let run = try fixture.run("override", fixture.file.path, "Board/Chip/Label", "fill=#FF0000", "--as", "t")

        #expect(run.status == 0)
        #expect(try written(fixture) == editorResult(.override(["fill": "#FF0000"]), at: "Board/Chip/Label"))
    }

    @Test("An out-of-range value is a usage error that names the range")
    func outOfRange() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let run = try fixture.run("set", fixture.file.path, "Board/Row/Flow", "common.opacity=7", "--as", "t")

        #expect(run.status == 2)
        #expect(run.stderr.contains("0 to 1"))
    }

    @Test("A mistyped binding and an in-flow x are usage errors")
    func bindingAndPosition() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let binding = try fixture.run("set", fixture.file.path, "Board/Free", "common.opacity=$brand", "--as", "t")
        let position = try fixture.run("override", fixture.file.path, "Board/Chip/Label", "x=10", "--as", "t")

        #expect(binding.status == 2)
        #expect(binding.stderr.contains("color"))
        #expect(position.status == 2)
        #expect(position.stderr.contains("layoutPosition"))
    }

    @Test("A file holding out-of-range values opens for reading and for other writes")
    func opensOutOfRange() throws {
        let fixture = try CommandFixture(fixture: "planner.pen")
        let tree = try fixture.run("tree", fixture.file.path)
        let write = try fixture.run("set", fixture.file.path, "Board/Row/Caption", "kind.content=Hey", "--as", "t")

        #expect(tree.status == 0)
        #expect(write.status == 0)
    }
}
