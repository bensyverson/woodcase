//
//  InjectedAddressCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The verbs, on the address `tree --expand` prints for a child an instance injects
/// into a component's slot frame.
///
/// A row an agent can read but not act on is a dead end, so the id printed there has
/// to survive a round trip: `get` answers it, `override` writes to it (into the slot's
/// children), and the verbs that cannot act on it say what to run instead.
@Suite("woodcase, on an injected slot child")
struct InjectedAddressCommandTests {
    // MARK: - Reading

    @Test("get answers the id path tree --expand prints")
    func getAnswersTheInjectedIDPath() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("get", fixture.file.path, "Inst0/Note0")

        #expect(run.status == 0, "\(run.stderr)")
        #expect((run.stdoutLines.first ?? "").hasPrefix("Inst0/Note0  Page/Filled/Body/Note  rev "))
        let body = run.stdoutLines.dropFirst().joined(separator: "\n")
        let node = try JSONDecoder().decode(PenNode.self, from: Data(body.utf8))
        #expect(node.common.name == "Note")
    }

    @Test("get answers the name path through the slot frame")
    func getAnswersTheInjectedNamePath() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("get", fixture.file.path, "Page/Filled/Body/Note")

        #expect(run.status == 0, "\(run.stderr)")
        #expect((run.stdoutLines.first ?? "").hasPrefix("Inst0/Note0  "))
    }

    @Test("get answers a descendant of an injected ref")
    func getAnswersInsideAnInjectedRef() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("get", fixture.file.path, "Inst0/Tag00/BTxt0")

        #expect(run.status == 0, "\(run.stderr)")
        #expect((run.stdoutLines.first ?? "").hasPrefix("Inst0/Tag00/BTxt0  Page/Filled/Body/Tag/BadgeText  rev "))
        // The override the injected ref carries is what renders, so it is what `get` says.
        #expect(run.stdout.contains(#""content": "live""#))
    }

    @Test("Every id tree --expand prints round-trips through get")
    func everyPrintedIDRoundTripsThroughGet() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let listing = try fixture.run("tree", fixture.file.path, "Page0", "--expand")
        #expect(listing.status == 0)
        let ids = listing.stdoutLines.dropFirst().compactMap { $0.split(separator: " ").last.map(String.init) }
        #expect(ids.contains("Inst0/Note0"))

        for id in ids {
            let run = try fixture.run("get", fixture.file.path, id)
            #expect(run.status == 0, "get \(id): \(run.stderr)")
            #expect((run.stdoutLines.first ?? "").hasPrefix("\(id)  "), "get \(id) answered \(run.stdoutLines.first ?? "")")
        }
    }

    // MARK: - Writing

    // `override` on an injected child is rewritten into the slot's children, where Pen
    // reads it: `SlotFillRewriteCommandTests`.

    // MARK: - The verbs that refuse

    @Test("set points at override rather than saying the address matches nothing")
    func setPointsAtOverride() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Inst0/Note0", "kind.content=Hi", "--as", "ana"
        )

        #expect(run.status != 0)
        #expect(!run.stderr.contains("matches no node"), "\(run.stderr)")
        #expect(run.stderr.contains("woodcase override"), "\(run.stderr)")
    }

    @Test("rm of an injected child says to rewrite the slot's children")
    func removePointsAtTheSlot() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("rm", fixture.file.path, "Inst0/Note0", "--as", "ana")

        #expect(run.status != 0)
        #expect(!run.stderr.contains("matches no node"), "\(run.stderr)")
        #expect(run.stderr.contains("children="), "\(run.stderr)")
        #expect(run.stderr.contains("Page/Filled/Body"), "\(run.stderr)")
    }
}
