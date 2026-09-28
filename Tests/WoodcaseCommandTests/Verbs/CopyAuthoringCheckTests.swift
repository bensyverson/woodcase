//
//  CopyAuthoringCheckTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A `cp`'s path-keyed properties are authored input like any other: a key a fill or
/// effect does not claim, and a node type the format does not have, are refused — also
/// when the copy is a component instance and the properties become overrides, and also
/// through `override` itself. Nothing is written when one is refused.
@Suite("Authoring check on a copy's nested properties")
struct CopyAuthoringCheckTests {
    private func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: "preserved-extras.pen")
    }

    @Test("cp of a plain node refuses a nested fill with an unknown key")
    func deepCopyRefusesUnknownFillKey() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "cp", fixture.file.path, "Board", "document",
            ##"Card/kind.fills={"type":"color","color":"#FFFFFF","glossy":true}"##, "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("glossy"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("cp of a component refuses a nested fill with an unknown key")
    func instanceCopyRefusesUnknownFillKey() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "cp", fixture.file.path, "Comp", "document",
            ##"Label/kind.fills={"type":"color","color":"#FFFFFF","glossy":true}"##, "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("glossy"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("cp of a component refuses a nested effect of an unknown type")
    func instanceCopyRefusesUnknownEffectType() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "cp", fixture.file.path, "Comp", "document",
            #"Label/kind.effects={"type":"glow","radius":2}"#, "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("glow"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("cp of a component refuses replacing a descendant with a node of an unknown type")
    func instanceCopyRefusesUnknownReplacementType() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "cp", fixture.file.path, "Comp", "document", "Label/type=video_clip", "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("video_clip"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("cp of a component refuses filling a slot with a node of an unknown type")
    func instanceCopyRefusesUnknownSlotChild() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "cp", fixture.file.path, "Comp", "document",
            #"Slot/children=[{"id":"Clip1","type":"video_clip","name":"Clip"}]"#, "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("video_clip"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("override refuses a fill with an unknown key")
    func overrideRefusesUnknownFillKey() throws {
        let fixture = try fixture()
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "override", fixture.file.path, "Inst/Label",
            ##"fill={"type":"color","color":"#FFFFFF","glossy":true}"##, "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("glossy"), "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("cp of a component still takes a well-formed nested fill and slot child")
    func instanceCopyTakesWellFormedValues() throws {
        let fixture = try fixture()

        let run = try fixture.run(
            "cp", fixture.file.path, "Comp", "document", "common.name=Comp2",
            ##"Label/kind.fills={"type":"color","color":"#FFFFFF"}"##,
            #"Slot/children=[{"id":"Box1","type":"rectangle","name":"Box","width":4,"height":4}]"#,
            "--as", "ana"
        )

        #expect(run.status == 0, "\(run.stderr)")
    }
}
