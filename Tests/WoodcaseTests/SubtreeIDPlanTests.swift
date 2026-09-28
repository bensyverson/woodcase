//
//  SubtreeIDPlanTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``SubtreeIDPlan`` settles the ids an authored subtree carries: it keeps what
/// the author supplied, draws what they left out, and rewrites the references
/// inside the subtree that the draws moved.
struct SubtreeIDPlanTests {
    // MARK: - Building blocks

    /// A frame with the given id and inline children.
    private func frame(_ id: String, _ name: String, children: [PenNode] = []) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .frame(PenNode.FrameData(children: children.isEmpty ? nil : children))
        )
    }

    /// A text node with the given id.
    private func text(_ id: String, _ name: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: name), kind: .text(PenNode.TextData(content: .literal(name))))
    }

    /// A ref node pointing at `target`, with optional descendant overrides.
    private func ref(
        _ id: String,
        _ name: String,
        to target: String,
        descendants: [String: PenDescendantOverride]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .ref(PenNode.RefData(ref: target, descendants: descendants))
        )
    }

    /// Every id in an inline subtree, outermost first.
    private func ids(of node: PenNode) -> [String] {
        [node.id] + node.kind.inlineChildren.flatMap(ids(of:))
    }

    // MARK: - The id grammar

    @Test("An id is any non-empty string without a slash, which is the .pen format's own rule")
    func idGrammar() {
        #expect(PenID.isValid("ALu8G"))
        #expect(PenID.isValid("hero-card"))
        #expect(PenID.isValid("V:btnBase"))
        #expect(!PenID.isValid(""))
        #expect(!PenID.isValid("Card/Title"))
    }

    @Test("A generated id satisfies the grammar")
    func generatedIDsAreValid() {
        for _ in 0 ..< 50 {
            #expect(PenID.isValid(PenID.generate()))
        }
    }

    // MARK: - Keeping what was supplied

    @Test("A supplied id survives, and a node that omitted one is given a fresh id")
    func keepsSuppliedAndFillsOmitted() throws {
        let subtree = frame("Hero", "Hero", children: [text("", "Caption")])

        let plan = try SubtreeIDPlan.keeping(subtree, avoiding: ["Cd101"])
        let settled = plan.applied(to: subtree)

        #expect(settled.id == "Hero")
        let caption = try #require(settled.kind.inlineChildren.first)
        #expect(!caption.id.isEmpty)
        #expect(caption.id != "Cd101")
        #expect(PenID.isValid(caption.id))
        // Only the drawn id counts as a replacement: nothing referred to "" .
        #expect(plan.replacements.isEmpty)
    }

    @Test("An id the document already holds is refused, not quietly replaced")
    func suppliedIDCollidingWithTheDocument() {
        let subtree = frame("Cd101", "Hero")

        #expect(throws: EditingError.duplicateNodeID(id: "Cd101")) {
            try SubtreeIDPlan.keeping(subtree, avoiding: ["Cd101"])
        }
    }

    @Test("Two nodes in the subtree sharing an id are refused, even though the document has neither")
    func suppliedIDsCollidingWithEachOther() {
        let subtree = frame("Hero", "Hero", children: [text("Dup", "One"), text("Dup", "Two")])

        #expect(throws: EditingError.duplicateNodeID(id: "Dup")) {
            try SubtreeIDPlan.keeping(subtree, avoiding: [])
        }
    }

    @Test("A supplied id with a slash in it is refused: it could never be addressed")
    func suppliedIDBreakingTheGrammar() {
        let subtree = frame("Hero/Card", "Hero")

        #expect(throws: EditingError.invalidNodeID(id: "Hero/Card")) {
            try SubtreeIDPlan.keeping(subtree, avoiding: [])
        }
    }

    @Test("A drawn id avoids the document's ids and the subtree's own")
    func drawnIDsAreDisjoint() throws {
        let subtree = frame("", "Hero", children: [text("", "One"), text("Keep", "Two"), text("", "Three")])

        let plan = try SubtreeIDPlan.keeping(subtree, avoiding: ["Cd101", "Cd201"])
        let settled = plan.applied(to: subtree)

        let assigned = ids(of: settled)
        #expect(assigned.count == 4)
        #expect(assigned[2] == "Keep")
        #expect(Set(assigned).count == 4)
        #expect(Set(assigned).isDisjoint(with: ["Cd101", "Cd201"]))
    }

    // MARK: - Regenerating everything

    @Test("Regenerating replaces every id, supplied or not, and records the mapping")
    func regeneratingReplacesEverything() {
        let subtree = frame("Hero", "Hero", children: [text("Cap", "Caption")])

        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: ["Cd101"])
        let settled = plan.applied(to: subtree)

        #expect(settled.id != "Hero")
        #expect(settled.kind.inlineChildren[0].id != "Cap")
        #expect(plan.replacements["Hero"] == settled.id)
        #expect(plan.replacements["Cap"] == settled.kind.inlineChildren[0].id)
        #expect(Set(ids(of: settled)).isDisjoint(with: ["Cd101"]))
    }

    // MARK: - Internal references

    @Test("A ref pointing inside the subtree follows the node it points at")
    func refInsideTheSubtreeIsRewritten() {
        let subtree = frame("Kit", "Kit", children: [
            frame("Btn", "Button"),
            ref("Use", "Instance", to: "Btn"),
        ])

        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: [])
        let settled = plan.applied(to: subtree)

        let button = settled.kind.inlineChildren[0]
        guard case let .ref(data) = settled.kind.inlineChildren[1].kind else {
            Issue.record("expected a ref node")
            return
        }
        #expect(button.id != "Btn")
        #expect(data.ref == button.id)
    }

    @Test("A ref pointing outside the subtree is left exactly as it was")
    func refOutsideTheSubtreeIsUntouched() {
        let subtree = frame("Board", "Board", children: [ref("Use", "Chip", to: "Cmp01")])

        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: ["Cmp01"])
        let settled = plan.applied(to: subtree)

        guard case let .ref(data) = settled.kind.inlineChildren[0].kind else {
            Issue.record("expected a ref node")
            return
        }
        #expect(data.ref == "Cmp01")
    }

    @Test("Descendant override keys follow the component's ids when the component moved with it")
    func descendantKeysAreRewritten() throws {
        let subtree = frame("Kit", "Kit", children: [
            frame("Btn", "Button", children: [text("Lbl", "Label")]),
            ref("Use", "Instance", to: "Btn", descendants: [
                "Lbl": PenDescendantOverride(properties: ["content": .string("Go")]),
                "Btn/Lbl": PenDescendantOverride(properties: ["content": .string("Nested")]),
            ]),
        ])

        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: [])
        let settled = plan.applied(to: subtree)

        let newButton = try #require(plan.replacements["Btn"])
        let newLabel = try #require(plan.replacements["Lbl"])
        guard case let .ref(data) = settled.kind.inlineChildren[1].kind else {
            Issue.record("expected a ref node")
            return
        }
        let keys = try #require(data.descendants).keys.sorted()
        #expect(keys.contains(newLabel))
        #expect(keys.contains("\(newButton)/\(newLabel)"))
        #expect(!keys.contains("Lbl"))
    }

    @Test("Descendant override keys of a ref pointing outside the subtree are left alone")
    func descendantKeysOfAnExternalRefAreUntouched() throws {
        let subtree = frame("Board", "Board", children: [
            text("Lbl", "Label"),
            ref("Use", "Chip", to: "Cmp01", descendants: [
                "Lbl": PenDescendantOverride(properties: ["content": .string("Go")]),
            ]),
        ])

        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: ["Cmp01"])
        let settled = plan.applied(to: subtree)

        guard case let .ref(data) = settled.kind.inlineChildren[1].kind else {
            Issue.record("expected a ref node")
            return
        }
        // "Lbl" here names a descendant of Cmp01, which did not move.
        #expect(try #require(data.descendants).keys.sorted() == ["Lbl"])
    }

    @Test("Everything other than the ids is carried through unchanged")
    func nonIDFieldsSurvive() {
        var hero = frame("Hero", "Hero", children: [text("Cap", "Caption")])
        hero.common.x = .literal(12)
        hero.common.reusable = true

        let plan = SubtreeIDPlan.regenerating(hero, avoiding: [])
        let settled = plan.applied(to: hero)

        #expect(settled.common.name == "Hero")
        #expect(settled.common.x?.literalValue == 12)
        #expect(settled.common.reusable == true)
        #expect(settled.kind.inlineChildren[0].common.name == "Caption")
    }
}
