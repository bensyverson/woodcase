//
//  RefRepointCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Repointing a nested instance at a sibling component — the natural way to say
/// "this tab is the current one" — driven through the binary.
///
/// The expander has always honoured such an override; the *reads* did not, so a
/// repointed instance came back with no rect and its old component's children, and
/// every address inside it stopped resolving. This suite pins the round trip:
/// repoint, read the new component's geometry and children, edit through them, then
/// repoint back and get the original reading again.
@Suite("woodcase repoints a nested instance")
struct RefRepointCommandTests {
    /// `Page1 > ref Sht01 → ShtC > ref Tab01 → PlnC (60×20, "Plain")`, with a sibling
    /// component `CurC` (90×24, "Current") to repoint at.
    private static let penFile = "ref-repoint-nested.pen"

    /// The rows of an expanded tree read, keyed by id.
    private func rows(_ fixture: CommandFixture, root: String) throws -> [String: TreeRow] {
        let run = try fixture.run("tree", fixture.file.path, root, "--expand", "--json")
        #expect(run.status == 0, "tree failed: \(run.stderr)")
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        return Dictionary(uniqueKeysWithValues: report.rows.map { ($0.id, $0) })
    }

    @Test("A repointed nested instance settles at the new component, and back again")
    func repointAndRestoreSettle() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)

        let before = try rows(fixture, root: "Sht01")
        #expect(before["Sht01/Tab01"]?.rect?.width == 60)
        #expect(before["Sht01/Tab01/Lbl01"] != nil)

        let repoint = try fixture.run("override", fixture.file.path, "Sht01/Tab01", "ref=CurC")
        #expect(repoint.status == 0, "override failed: \(repoint.stderr)")

        let after = try rows(fixture, root: "Sht01")
        #expect(after["Sht01/Tab01"]?.rect?.width == 90)
        #expect(after["Sht01/Tab01/Lbl02"] != nil)
        #expect(after["Sht01/Tab01/Lbl01"] == nil)

        let restore = try fixture.run("override", fixture.file.path, "Sht01/Tab01", "ref=PlnC")
        #expect(restore.status == 0, "restoring override failed: \(restore.stderr)")

        let restored = try rows(fixture, root: "Sht01")
        #expect(restored["Sht01/Tab01"]?.rect?.width == 60)
        #expect(restored["Sht01/Tab01/Lbl01"] != nil)
        #expect(restored["Sht01/Tab01/Lbl02"] == nil)
    }

    @Test("Every address inside a repointed instance is one the read verbs accept")
    func addressesInsideARepointedInstanceResolve() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        let repoint = try fixture.run("override", fixture.file.path, "Sht01/Tab01", "ref=CurC")
        #expect(repoint.status == 0)

        let get = try fixture.run("get", fixture.file.path, "Sht01/Tab01/Lbl02")
        #expect(get.status == 0, "get failed: \(get.stderr)")

        let stale = try fixture.run("get", fixture.file.path, "Sht01/Tab01/Lbl01")
        #expect(stale.status == ExitCode.usage.rawValue)
    }

    @Test("An override written into a repointed instance reaches the new component's node")
    func overrideInsideARepointedInstance() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        #expect(try fixture.run("override", fixture.file.path, "Sht01/Tab01", "ref=CurC").status == 0)

        let write = try fixture.run("override", fixture.file.path, "Sht01/Tab01/Lbl02", "content=Now")
        #expect(write.status == 0, "override failed: \(write.stderr)")

        let read = try fixture.run(
            "tree", fixture.file.path, "Sht01", "--expand", "--json", "--props", "kind.content"
        )
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(read.stdout.utf8))
        let label = try #require(report.rows.first { $0.id == "Sht01/Tab01/Lbl02" })
        #expect(label.properties?["kind.content"] == .string("Now"))
    }
}
