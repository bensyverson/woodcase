//
//  ScriptSlotFillTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// `doc.override` on content an instance wrote into its own slot goes the way the verb
/// goes: into the slot's `children`, with a note naming the slot.
@Suite("doc.override on an instance's own slot content")
struct ScriptSlotFillTests {
    @Test("doc.override rewrites into the slot fill and its report names the slot")
    func overrideRewritesIntoTheFill() throws {
        let document = try ScriptFixture.document("slot-fill.pen")

        let run = ScriptHost.run(
            [.text("doc.override('Inst0/Note0', { content: 'Hi' })", name: "<argv>")], over: document
        )

        #expect(run.error == nil, "the script failed: \(run.error?.message ?? "")")
        guard case let .ref(data) = document.nodes["Inst0"]?.kind else {
            Issue.record("Inst0 should still be an instance")
            return
        }
        #expect(Set((data.descendants ?? [:]).keys) == ["CSlt0"])
        guard case let .array(children)? = data.descendants?["CSlt0"]?.properties["children"],
              case let .dictionary(note)? = children.first
        else {
            Issue.record("the slot fill is gone")
            return
        }
        #expect(note["content"] == .string("Hi"))

        guard case let .dictionary(report)? = run.result,
              case let .array(divergences)? = report["divergences"],
              case let .dictionary(rewrite)? = divergences.first
        else {
            Issue.record("the report carries no divergence: \(String(describing: run.result))")
            return
        }
        #expect(rewrite["kind"] == .string("slotFillRewrite"))
        #expect(rewrite["applied"] == .string("Page/Filled/Body"))
    }
}
