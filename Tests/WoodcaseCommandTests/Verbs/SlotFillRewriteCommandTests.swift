//
//  SlotFillRewriteCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `override`, `apply` and `undo` on content an instance wrote into its own slot.
///
/// Pen drops a `descendants` key naming such content, so the write is rewritten into the
/// slot's `children` and the answer says where it landed: the address typed leads, and a
/// note names the slot written (`project/2026-09-26-slot-override-keys.md`).
@Suite("woodcase, overriding an instance's own slot content")
struct SlotFillRewriteCommandTests {
    /// The descendants map of `Inst0` as the file holds it.
    private func descendants(in fixture: CommandFixture) throws -> [String: PenDescendantOverride] {
        let document = try EditableDocument(from: PenParser.parse(contentsOf: fixture.file))
        guard case let .ref(data) = document.nodes["Inst0"]?.kind else { return [:] }
        return data.descendants ?? [:]
    }

    /// The injected `Note0` as the slot's `children` hold it.
    private func note(in fixture: CommandFixture) throws -> [String: AnyCodable]? {
        guard case let .array(children)? = try descendants(in: fixture)["CSlt0"]?.properties["children"]
        else { return nil }
        for case let .dictionary(node) in children where node["id"] == .string("Note0") {
            return node
        }
        return nil
    }

    @Test("override writes into the slot's children and says so", arguments: [
        "Inst0/Note0", "Page/Filled/Body/Note",
    ])
    func overrideRewritesIntoTheFill(address: String) throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let write = try fixture.run("override", fixture.file.path, address, "content=Hi", "--as", "ana")

        #expect(write.status == 0, "\(write.stderr)")
        #expect(write.stdoutLines.first == "Page/Filled  Inst0")
        let noteLine = try #require(write.stdoutLines.first { $0.hasPrefix("note  ") })
        #expect(noteLine.contains("Inst0/Note0"), "\(noteLine)")
        #expect(noteLine.contains("Page/Filled/Body"), "\(noteLine)")
        #expect(try Set(descendants(in: fixture).keys) == ["CSlt0"])
        #expect(try note(in: fixture)?["content"] == .string("Hi"))

        let tree = try fixture.run("tree", fixture.file.path, "Inst0", "--expand", "--props", "kind.content")
        #expect(tree.stdout.contains("Hi"), "\(tree.stdout)")
    }

    @Test("override --json names the slot the change landed in")
    func jsonNamesTheSlot() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let write = try fixture.run(
            "override", fixture.file.path, "Inst0/Note0", "content=Hi", "--as", "ana", "--json"
        )

        #expect(write.status == 0, "\(write.stderr)")
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(write.stdout.utf8))
        #expect(report.id == "Inst0")
        let rewrite = try #require(report.divergences?.first { $0.kind == .slotFillRewrite })
        #expect(rewrite.requested == "Inst0/Note0")
        #expect(rewrite.applied == "Page/Filled/Body")
    }

    @Test("A node inside an injected ref is written on that ref inside the fill")
    func injectedRefDescendant() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let write = try fixture.run("override", fixture.file.path, "Inst0/Tag00/BTxt0", "content=Hi", "--as", "ana")

        #expect(write.status == 0, "\(write.stderr)")
        #expect(try Set(descendants(in: fixture).keys) == ["CSlt0"])
        let get = try fixture.run("get", fixture.file.path, "Inst0/Tag00/BTxt0")
        #expect(get.stdout.contains(#""content": "Hi""#), "\(get.stdout)")
    }

    @Test("apply rewrites a batch line the same way")
    func applyRewrites() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let ops = fixture.root.appendingPathComponent("ops.jsonl")
        try #"{"op":"override","target":"Inst0/Note0","props":{"content":"Hi"}}"#
            .write(to: ops, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", ops.path, "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("Page/Filled/Body"), "\(run.stdout)")
        #expect(try Set(descendants(in: fixture).keys) == ["CSlt0"])
        #expect(try note(in: fixture)?["content"] == .string("Hi"))
    }

    @Test("undo restores the fill the override rewrote")
    func undoRestoresTheFill() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let before = try descendants(in: fixture)

        let write = try fixture.run("override", fixture.file.path, "Inst0/Note0", "content=Hi", "--as", "ana")
        #expect(write.status == 0, "\(write.stderr)")

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0, "\(undo.stderr)")
        #expect(try descendants(in: fixture) == before)
    }

    @Test("set on an injected child points at override on the same address")
    func setPointsAtOverrideOnTheAddress() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")

        let run = try fixture.run("set", fixture.file.path, "Inst0/Note0", "kind.content=Hi", "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("woodcase override \(fixture.file.path) Inst0/Note0"), "\(run.stderr)")
    }
}
