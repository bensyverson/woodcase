//
//  OverrideNullTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// What `override key=null` means, and when the write says so.
///
/// A null override is stored, not removed, and its consequence depends entirely on the
/// definition: where the component sets the key, the null takes that value away, which
/// is a destructive edit the write names; where the component sets nothing, the null
/// patches nothing and the write stays quiet.
@Suite("woodcase override key=null")
struct OverrideNullTests {
    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    @Test("A null over a value the definition sets is stored, and the write says what it did")
    func nullOverAValueTheDefinitionSetsWarns() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "content=null", "--as", "ana"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"] == .null)
        #expect(run.stdoutLines.count == 4)
        #expect(run.stdoutLines[1].contains("Dashboard/Body/Nav/Label"))
        #expect(run.stdoutLines[1].contains("unset"))
    }

    @Test("A null over a property the definition leaves unset is a no-op, and stays quiet")
    func nullOverAnUnsetPropertyIsQuiet() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "fontSize=null", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
    }
}
