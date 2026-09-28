//
//  OverrideCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase override` writes into a component instance's `descendants` map, which
/// is the one place the CLI speaks raw .pen property names.
@Suite("woodcase override")
struct OverrideCommandTests {
    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    @Test("A property is written onto the instance, and the answer names the instance")
    func overridesADescendant() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "content=Menu2", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 3)
        #expect(lines[0] == "Dashboard/Body/Nav  Nav01")
        #expect(lines[1].hasPrefix("rev  "))
        #expect(lines[2].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"]
            == .string("Menu2"))

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .override)
    }

    @Test("A nested instance descendant is keyed the way Pen keys it")
    func overridesANestedDescendant() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Badge/Count", "content=\"9\""
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Bdg01/Cnt01"]?.properties["content"]
            == .string("9"))
    }

    @Test("-F reads the properties from a JSON object of raw .pen names")
    func overridesFromAFile() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let url = fixture.root.appendingPathComponent("props.json")
        try #"{"content": "From a file"}"#.write(to: url, atomically: true, encoding: .utf8)

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "-F", url.path
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"]
            == .string("From a file"))
    }

    @Test("A node that is not inside an instance is sent to set, in CLI words")
    func outsideAnInstanceIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Header/Title", "content=Hi"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase set"))
        #expect(!run.stderr.contains("{\"op\""))
    }

    @Test("override with nothing to override is refused rather than doing nothing")
    func noPropertiesIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav/Label")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("key=value"))
    }

    @Test("Overriding a property the definition leaves unset notes what the write means")
    func overrideOfAnUnsetPropertyEchoes() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "fontSize=18", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 4)
        #expect(run.stdoutLines[1] == """
        note  Dashboard/Body/Nav/Label adds fontSize rather than replacing it — Button \
        does not set fontSize, which is how an instance varies from its component
        """)
    }

    @Test("The help's own example applies: content=42 is stored as the text 42")
    func theHelpExampleApplies() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "content=42", "--as", "ana"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"]
            == .string("42"))
        #expect(run.stdoutLines[1] == """
        content stored the number 42 as the text "42" — the property takes text, not a number
        """)
    }

    @Test("A property path is translated to the raw key the map uses, not stored as written")
    func aPropertyPathIsTranslated() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "kind.content=Menu2"
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
        let probe = try PenFileProbe(fixture.file)
        let written = overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties
        #expect(written?["content"] == .string("Menu2"))
        #expect(written?["kind.content"] == nil)
    }

    @Test("A value the node's type cannot take is refused, and the file is untouched")
    func aValueTheNodeCannotTakeIsRefused() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", #"content={"a":1}"#
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("content"))
        #expect(run.stderr.contains("Dashboard/Body/Nav/Label"))
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Dashboard/Body/Nav"))["Lbl01"]?.properties["content"]
            == .string("Menu"))
    }

    @Test("A stale --rev is a conflict, exit 3, naming the instance")
    func staleRevision() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav/Label", "content=Menu2",
            "--rev", "0000000000000000"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Dashboard/Body/Nav"))
    }
}
