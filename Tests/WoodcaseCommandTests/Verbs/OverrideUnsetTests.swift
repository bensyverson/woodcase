//
//  OverrideUnsetTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase override --unset` removes an override, where `key=null` stores one.
///
/// The two read the same in `get` — a key that is there — and mean opposite things
/// when the instance expands: a null clears the definition's value, while removing the
/// entry shows it again. These tests pin the difference at the surface an agent sees.
@Suite("woodcase override --unset")
struct OverrideUnsetTests {
    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    @Test("--unset removes the override so the definition's value shows again")
    func unsetRemovesTheOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "--unset", "content", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"] == nil)

        let expanded = try fixture.run("get", fixture.file.path, "Dashboard/Body/Nav/Label")
        #expect(expanded.status == 0)
        #expect(expanded.stdout.contains("Click"))
    }

    @Test("--unset is repeatable and leaves the keys it does not name alone")
    func unsetIsRepeatable() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let seeded = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "fontSize=18", "opacity=0.5"
        )
        #expect(seeded.status == 0)

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label",
            "--unset", "fontSize", "--unset", "content"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        let written = overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties
        #expect(written?["fontSize"] == nil)
        #expect(written?["content"] == nil)
        #expect(written?["opacity"] == .double(0.5))
    }

    @Test("--unset takes a property path as well as a raw .pen name")
    func unsetTakesAPropertyPath() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "--unset", "kind.content"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"] == nil)
    }

    @Test("--unset and key=value may be written on the same command")
    func unsetAlongsideAnAssignment() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let seeded = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "fontSize=18"
        )
        #expect(seeded.status == 0)

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label",
            "content=Menu2", "--unset", "fontSize"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        let written = overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties
        #expect(written?["content"] == .string("Menu2"))
        #expect(written?["fontSize"] == nil)
    }

    @Test("The same key assigned and unset on one command is refused")
    func unsettingAnAssignedKeyIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label",
            "content=Menu2", "--unset", "content"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("content"))
    }

    @Test("An undo puts back exactly the override --unset removed")
    func undoRestoresTheOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "--unset", "content", "--as", "ana"
        )
        #expect(run.status == 0)

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0)

        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"]
            == .string("Menu"))
    }

    @Test("An undo removes an override the write added, rather than leaving it behind")
    func undoRemovesAnAddedOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "fontSize=18", "--as", "ana"
        )
        #expect(run.status == 0)

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0)

        let probe = try PenFileProbe(fixture.file)
        let written = overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties
        #expect(written?["fontSize"] == nil)
        #expect(written?["content"] == .string("Menu"))
    }

    @Test("The batch override op takes unset with the same meaning")
    func batchUnset() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let line = """
        {"op":"override","target":"Dashboard/Body/Nav/Label","unset":["content"]}
        """

        let run = try fixture.run(["apply", fixture.file.path, "-F", "-"], stdin: Data(line.utf8))

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"] == nil)
    }

    @Test("override with neither an assignment nor --unset is refused")
    func nothingToDoIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav/Label")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--unset"))
    }

    @Test("override --help teaches the difference between null and --unset")
    func helpTeachesTheDifference() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("--unset"))
        #expect(run.stdout.contains("null"))
    }
}
