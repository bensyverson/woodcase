//
//  TreeSlotExpandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// What `woodcase tree --expand` prints for a slot an instance filled.
///
/// The rows exist to be read back: a writer who has just filled a slot has no other
/// cheap way to see what is in it.
struct TreeSlotExpandTests {
    @Test("--expand prints the children an instance injects into a slot, by id path")
    func expandPrintsInjectedChildren() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("tree", fixture.file.path, "Page0", "--expand")

        #expect(run.status == 0)
        #expect(run.stdout.contains("Inst0/Note0"))
        #expect(run.stdout.contains("Inst0/Tag00"))
        #expect(run.stdout.contains("Inst0/Tag00/BTxt0"))
    }

    @Test("Without --expand the instance stays one row and the injected children are hidden")
    func withoutExpandNothingIsInjected() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("tree", fixture.file.path, "Page0")

        #expect(run.status == 0)
        #expect(!run.stdout.contains("Note0"))
    }

    @Test("lint reports nothing about the definition's empty slot frame")
    func lintLeavesTheSlotAlone() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("lint", fixture.file.path, "Card0")

        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }
}
