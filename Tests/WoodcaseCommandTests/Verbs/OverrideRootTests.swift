//
//  OverrideRootTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase override <instance> key=value` — with no descendant path — writes the
/// component root's own properties as this instance sees them.
///
/// The format calls them root overrides and writes them as the ref node's own
/// non-reserved top-level keys. The instance has one address either way: `set` writes
/// the ref node, `override` writes what the ref shows.
@Suite("woodcase override on an instance root")
struct OverrideRootTests {
    /// The root overrides an instance carries, keyed as Pen keys them.
    private func rootOverrides(of instance: PenNode?) -> [String: AnyCodable] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.rootOverrides ?? [:]
    }

    @Test("A property on the instance itself is written as a root override")
    func writesARootOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav", "width=200", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 3)
        #expect(lines[0] == "Dashboard/Body/Nav  Nav01")

        let probe = try PenFileProbe(fixture.file)
        #expect(rootOverrides(of: probe.node("Dashboard/Body/Nav"))["width"] == .int(200))
        #expect(probe.node("Button")?.frameWidth == .fixed(120))

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.first?.op == .override)
    }

    @Test("The render shows the overridden root, not the definition's value")
    func theRenderReflectsIt() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let written = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "width=200")
        #expect(written.status == 0)

        let expanded = try fixture.run("get", fixture.file.path, "Dashboard/Body/Nav", "--expand", "--json")

        #expect(expanded.status == 0)
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(expanded.stdout.utf8))
        #expect(report.node.frameWidth == .fixed(200))
    }

    @Test("A property path is translated to the raw key the format writes")
    func aPropertyPathIsTranslated() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "kind.width=200")

        #expect(run.status == 0)
        let written = try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav"))
        #expect(written["width"] == .int(200))
        #expect(written["kind.width"] == nil)
    }

    @Test("A root override the definition does not set echoes what the write means")
    func anAddedRootPropertyEchoes() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav", "cornerRadius=8"
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 4)
        #expect(run.stdoutLines[1] == """
        note  Dashboard/Body/Nav adds cornerRadius rather than replacing it — Button \
        does not set cornerRadius, which is how an instance varies from its component
        """)
    }

    @Test("--unset removes a root override")
    func unsetRemovesARootOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let written = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "width=200")
        #expect(written.status == 0)

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "--unset", "width")

        #expect(run.status == 0)
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav")).isEmpty)
    }

    @Test("A value the component root cannot take is refused, and the file is untouched")
    func aValueTheRootCannotTakeIsRefused() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", #"width=[1,2]"#)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("width"))
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav")).isEmpty)
    }

    @Test("A key the ref node carries itself is refused, naming set")
    func aReservedCommonKeyNamesSet() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "opacity=0.5")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase set"))
        #expect(run.stderr.contains("common.opacity"))
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav")).isEmpty)
    }

    @Test("The structural keys of a ref are refused, naming set")
    func aStructuralKeyNamesSet() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Body/Nav", "ref=Bge01")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("kind.ref"))
    }

    @Test("set on a component-root property is refused, naming override")
    func setOnARootPropertyNamesOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("set", fixture.file.path, "Dashboard/Body/Nav", "kind.width=200")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase override"))
        #expect(run.stderr.contains("Dashboard/Body/Nav width="))
    }

    @Test("set still writes the ref node's own properties")
    func setStillWritesTheRefNode() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("set", fixture.file.path, "Dashboard/Body/Nav", "common.opacity=0.5")

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Dashboard/Body/Nav")?.common.opacity == .literal(0.5))
        #expect(rootOverrides(of: probe.node("Dashboard/Body/Nav")).isEmpty)
    }

    @Test("A node that is neither an instance nor inside one is still sent to set")
    func aPlainNodeIsStillSentToSet() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", fixture.file.path, "Dashboard/Header/Title", "content=Hi")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase set"))
    }

    @Test("The batch override op writes a root override from the same address")
    func batchWritesARootOverride() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let line = """
        {"op":"override","target":"Dashboard/Body/Nav","props":{"width":200}}
        """

        let run = try fixture.run(["apply", fixture.file.path, "-F", "-"], stdin: Data(line.utf8))

        #expect(run.status == 0)
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav"))["width"]
            == .int(200))
    }

    @Test("An undo puts the instance back exactly as it was")
    func undoRestoresTheInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "override", fixture.file.path, "Dashboard/Body/Nav", "width=200", "--as", "ana"
        )
        #expect(run.status == 0)

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0)
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Dashboard/Body/Nav")).isEmpty)
    }

    @Test("override --help says the instance's own address writes the root")
    func helpTeachesTheRootForm() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run("override", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("root"))
    }
}
