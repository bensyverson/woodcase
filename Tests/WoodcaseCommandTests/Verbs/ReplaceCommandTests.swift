//
//  ReplaceCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase replace` drives the binary end to end: the subtree file goes in, the node
/// keeps its id and its place, and one `replace` event goes into the activity log.
@Suite("woodcase replace")
struct ReplaceCommandTests {
    /// Writes a subtree file beside the fixture and returns its path.
    private func subtree(_ json: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("subtree-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// Rewrites the fixture copy in the canonical on-disk form, so that "the same
    /// bytes" is a meaningful thing to assert about a hand-written fixture.
    private func canonicalize(_ url: URL) throws {
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: url))).write(to: url)
    }

    // MARK: - The happy path

    @Test("The node keeps its id and its index, and the new children are addressable")
    func replacesInPlace() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(
            #"{"type":"frame","name":"Cards","layout":"horizontal","width":380,"height":200,"#
                + #""children":[{"type":"text","name":"Only","content":"one"}]}"#,
            in: fixture
        )

        let run = try fixture.run("replace", fixture.file.path, "Canvas/Cards", "-F", file, "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        #expect(lines.count == 4)
        #expect(lines[0] == "Cards  Crd01")
        #expect(lines[1].hasPrefix("  Only  "))
        #expect(lines[2].hasPrefix("rev  "))
        #expect(lines[3].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        let canvas = try #require(probe.node("Canvas"))
        #expect(PenFileProbe.children(of: canvas).map(\.common.name) == ["Title", "Cards"])
        #expect(probe.node("Canvas/Cards")?.id == "Crd01")
        #expect(probe.node("Canvas/Cards/Only")?.textContent == "one")
        #expect(probe.node("Canvas/Cards/First") == nil)

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .replace)
        #expect(page.events.first?.identity == "ana")
    }

    @Test("undo restores the previous subtree, byte for byte")
    func undoRestoresTheOldSubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)
        let file = try subtree(#"{"type":"frame","name":"Cards","children":[]}"#, in: fixture)

        #expect(try fixture.run("replace", fixture.file.path, "Canvas/Cards", "-F", file, "--as", "ana").status == 0)
        #expect(try Data(contentsOf: fixture.file) != before)

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(undo.status == 0)
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - Refusals

    @Test("A root id that is not the target's is refused, saying the id is kept")
    func refusesADifferentRootID() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"id":"Nope1","type":"frame","name":"Cards"}"#, in: fixture)

        let run = try fixture.run("replace", fixture.file.path, "Canvas/Cards", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nope1"))
        #expect(run.stderr.contains("Crd01"))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards/First") != nil)
    }

    @Test("Changing the root type of a reusable definition with instances is refused")
    func refusesAKindSwapOnALiveComponent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"text","name":"Component","content":"nope"}"#, in: fixture)

        let run = try fixture.run("replace", fixture.file.path, "Component", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Component"))
        #expect(run.stderr.contains("Board/Chip"))
        #expect(run.stderr.contains("frame"))
        #expect(try PenFileProbe(fixture.file).node("Component/Label") != nil)
    }

    @Test("An unnamed node in the replacement is refused")
    func refusesAnUnnamedNode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(
            #"{"type":"frame","name":"Cards","children":[{"type":"text","content":"hi"}]}"#,
            in: fixture
        )

        let run = try fixture.run("replace", fixture.file.path, "Canvas/Cards", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("name"))
    }

    @Test("A stale --rev is a conflict, and changes nothing")
    func staleRevisionIsAConflict() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"frame","name":"Cards","children":[]}"#, in: fixture)

        let run = try fixture.run(
            "replace", fixture.file.path, "Canvas/Cards", "-F", file, "--rev", "0000000000000000"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards/First") != nil)
    }

    @Test("A subtree file that is not a .pen node is a usage error naming the file")
    func refusesANonSubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree("not json", in: fixture)

        let run = try fixture.run("replace", fixture.file.path, "Canvas/Cards", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains(file))
    }

    // MARK: - Help

    @Test("replace --help carries a worked example and the address forms")
    func helpTeaches() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("replace", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("woodcase replace"))
        #expect(run.stdout.contains("EXAMPLE"))
        #expect(run.stdout.contains("keeps its id"))
    }
}
