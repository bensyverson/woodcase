//
//  PasteCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase paste` — a clip from `woodcase clip --json`, taken into a .pen file.
@Suite("woodcase paste")
struct PasteCommandTests {
    /// Copies `BtnI` out of the fixture into a clip file beside it.
    private func clip(in fixture: CommandFixture) throws -> URL {
        let run = try fixture.run("clip", fixture.file.path, "BtnI", "--json")
        #expect(run.status == 0)
        let url = fixture.root.appendingPathComponent("clip.json")
        try Data(run.stdout.utf8).write(to: url)
        return url
    }

    /// Writes an empty .pen beside the fixture.
    private func emptyFile(in fixture: CommandFixture) throws -> URL {
        let url = fixture.root.appendingPathComponent("empty.pen")
        try Data(#"{ "version": "2.17", "children": [] }"#.utf8).write(to: url)
        return url
    }

    @Test("A clip pasted into another file brings the components and variables it needs")
    func pasteIntoAnotherFile() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let clip = try clip(in: fixture)
        let target = try emptyFile(in: fixture)

        let run = try fixture.run("paste", target.path, clip.path, "--as", "ana")

        #expect(run.status == 0)
        let pasted = try PenParser.parse(Data(contentsOf: target))
        #expect(pasted.children.count == 3)
        #expect(pasted.variables?.keys.sorted() == ["accent", "brand"])
        #expect(pasted.themes?["mode"] == ["light", "dark"])
    }

    @Test("--into a stack puts the copy last and says what it reused")
    func intoStack() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let clip = try clip(in: fixture)

        let run = try fixture.run("paste", fixture.file.path, clip.path, "--into", "Page/Card", "--as", "ana", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(PasteCommand.Report.self, from: Data(run.stdout.utf8))
        #expect(report.reusedComponents == ["Btn": "Btn", "Icon": "Icon"])
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        let card = try document.materializeSubtree(rootID: "Card").kind.inlineChildren.map(\.id)
        #expect(card.last == report.insertedRootIDs.first)
    }

    @Test("A paste that closes a component loop is refused, naming it, and writes nothing")
    func loopRefused() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let clip = try clip(in: fixture)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("paste", fixture.file.path, clip.path, "--into", "Icon", "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("Icon → Button → Icon"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("--into a slot of an instance writes the copy into its fill")
    func intoSlot() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let slotted = fixture.root.appendingPathComponent("slots.pen")
        try Data("""
        {"version": "2.19", "children": [
          {"id": "Item", "type": "frame", "name": "Item", "reusable": true, "x": 0, "y": 0, "width": 100, "height": 20},
          {"id": "Screen", "type": "frame", "name": "Screen", "reusable": true, "x": 200, "y": 0, "width": 200,
           "height": "fit_content", "layout": "vertical", "children": [
            {"id": "List", "type": "frame", "name": "List", "slot": ["Item"], "width": "fill_container",
             "height": "fit_content", "layout": "vertical"}]},
          {"id": "Filled", "type": "ref", "ref": "Screen", "name": "Filled", "x": 500, "y": 0,
           "descendants": {"List": {"children": [{"id": "Row1", "type": "ref", "ref": "Item", "name": "Row 1"}]}}},
          {"id": "Loose", "type": "rectangle", "name": "Loose", "x": 0, "y": 300, "width": 30, "height": 30}
        ]}
        """.utf8).write(to: slotted)
        let clipRun = try fixture.run("clip", slotted.path, "Loose", "--json")
        #expect(clipRun.status == 0)
        let clip = fixture.root.appendingPathComponent("loose.json")
        try Data(clipRun.stdout.utf8).write(to: clip)

        let run = try fixture.run("paste", slotted.path, clip.path, "--into", "Filled/List", "--as", "ana", "--json")

        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(PasteCommand.Report.self, from: Data(run.stdout.utf8))
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: slotted)))
        #expect(document.slot("Filled/List")?.contentIDs.last == report.insertedRootIDs.first)
    }

    @Test("Two placements at once is a usage failure")
    func onePlacement() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let clip = try clip(in: fixture)

        let run = try fixture.run(
            "paste", fixture.file.path, clip.path, "--into", "Card", "--after", "Free", "--as", "ana"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--into and --after"))
        #expect(run.stderr.contains("pass one"))
    }
}
