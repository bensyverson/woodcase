//
//  SiblingOrderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The three-way merge of one child list (`project/2026-10-04-three-way-diff-design.md`,
/// algorithm step 4).
struct SiblingOrderTests {
    private func merge(_ base: String, _ ours: String, _ theirs: String, members: String? = nil) -> SiblingOrder.Outcome {
        let ids = { (text: String) in text.map(String.init) }
        let members = Set(ids(members ?? ours + theirs))
        return SiblingOrder.merge(base: ids(base), ours: ids(ours), theirs: ids(theirs), members: members)
    }

    @Test("Only theirs reordered: theirs' order")
    func theirsReordered() {
        #expect(merge("abc", "abc", "cba") == SiblingOrder.Outcome(order: ["c", "b", "a"], bothReordered: false))
    }

    @Test("Only ours reordered, or both alike: ours' order")
    func oursReordered() {
        #expect(merge("abc", "cba", "abc").order == ["c", "b", "a"])
        #expect(merge("abc", "cba", "cba") == SiblingOrder.Outcome(order: ["c", "b", "a"], bothReordered: false))
    }

    @Test("Both reordered differently: ours' order, flagged")
    func bothReordered() {
        #expect(merge("abc", "bac", "acb") == SiblingOrder.Outcome(order: ["b", "a", "c"], bothReordered: true))
    }

    @Test("A new member follows its nearest preceding sibling on its own side")
    func insertsFollowTheirAnchor() {
        #expect(merge("ab", "ab", "ayb").order == ["a", "y", "b"])
        #expect(merge("ab", "axb", "ab").order == ["a", "x", "b"])
        #expect(merge("ab", "ab", "yab").order == ["y", "a", "b"])
    }

    @Test("Two inserts after one anchor: ours' stays next to it, theirs' follows")
    func insertsAtOneAnchor() {
        #expect(merge("ab", "axb", "ayb").order == ["a", "x", "y", "b"])
        #expect(merge("ab", "xab", "yab").order == ["x", "y", "a", "b"])
    }

    @Test("A run of inserts keeps its own order")
    func insertRun() {
        #expect(merge("ab", "ab", "ayzb").order == ["a", "y", "z", "b"])
    }

    @Test("Only members are placed: leavers drop out, and a member one side reordered past a leaver keeps its place")
    func membersOnly() {
        #expect(merge("abc", "abc", "ac", members: "ac").order == ["a", "c"])
        #expect(merge("abc", "cb", "abc", members: "bc").order == ["c", "b"])
    }
}
