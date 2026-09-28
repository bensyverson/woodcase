//
//  DeepChainGuardTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `woodcase override` and `woodcase tree` against documents whose *instance* nesting
/// is deeper than any real design, the same way `TreeDeepNestingTests` drives frame and
/// component nesting.
///
/// `EditableDocument`'s descendant-key and injected-node walks
/// (`appendDescendantKeys`/`appendInjectedKeys` in `EditableDocument+DescendantKeys.swift`,
/// `collectInjected` in `EditableDocument+Injected.swift`) used to recurse one Swift
/// call per level, and now run from a work list instead
/// (`project/2026-09-26-debug-stack-depth.md`). ``DescendantWalkStackTests`` is the
/// stack-safety proof — it measures the two walks' own stack use directly and holds it
/// to a budget, which is what actually distinguishes the fixed walk from the old one at
/// these depths. This file is the complementary, end-to-end check: the CLI's own
/// `override` and `tree` verbs still resolve, validate and print correctly at depths a
/// real design never reaches, driving the debug binary in a child process — as
/// `TreeDeepNestingTests` does — so a regression here fails one test rather than the
/// whole suite.
struct DeepChainGuardTests {
    /// Reusable components chained end to end, each placing the next by `ref`. Far
    /// past where the old recursive walk overflowed a debug build's stack, and — since
    /// each component is only two nodes deep — nowhere near the ~255-level nesting a
    /// literal `.pen` file can even parse (`TreeDeepNestingTests.frameTreeDepth`'s own
    /// comment): the depth here is in how many *separate* components the walk steps
    /// through, not in how deeply any one of them is nested.
    private static let componentChainDepth = 4000

    /// Frames wrapping a component's own slot, deep enough to overflow the old
    /// recursive `collectInjected` in a debug build while staying under Foundation's
    /// ~255-level JSON nesting ceiling — the same ceiling `TreeDeepNestingTests` caps
    /// its own frame tree at.
    private static let slotNestingDepth = 230

    @Test("A chain of components each placing the next is walked for override targets, not recursed")
    func chainedComponentsDoNotRecurse() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let file = try Self.write(Self.chainedComponents(count: Self.componentChainDepth), named: "chain.pen", in: fixture)

        let run = try fixture.run("override", file.path, "Inst0", "width=20")

        #expect(run.status == 0, "stderr: \(run.stderr)")
    }

    @Test("A slot nested deep inside a component's own body is found, not recursed onto")
    func deeplyNestedSlotDoesNotRecurse() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let file = try Self.write(Self.deepSlotFill(depth: Self.slotNestingDepth), named: "deep-slot.pen", in: fixture)

        let run = try fixture.run("tree", file.path, "Inst0/Leaf0")

        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stdout.contains("Leaf0"), "stdout: \(run.stdout)")
    }

    // MARK: - Fixtures

    /// Writes a generated document beside the fixture's own file.
    private static func write(_ json: String, named name: String, in fixture: CommandFixture) throws -> URL {
        let url = fixture.root.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    /// `count` reusable frame components, `Cmp0` through `Cmp<count-1>`, each but the
    /// last holding one `ref` child that places the next; the last is a leaf. One
    /// instance, `Inst0`, places `Cmp0`.
    private static func chainedComponents(count: Int) -> String {
        var parts: [String] = []
        for index in 0 ..< count {
            if index < count - 1 {
                parts.append(
                    #"{"id": "Cmp\#(index)", "type": "frame", "reusable": true, "width": 10, "height": 10, "#
                        + #""children": [{"id": "Rf\#(index)", "type": "ref", "ref": "Cmp\#(index + 1)"}]}"#
                )
            } else {
                parts.append(#"{"id": "Cmp\#(index)", "type": "frame", "reusable": true, "width": 10, "height": 10}"#)
            }
        }
        parts.append(#"{"id": "Inst0", "type": "ref", "ref": "Cmp0"}"#)
        return #"{"version": "2.17", "children": [\#(parts.joined(separator: ", "))]}"#
    }

    /// One reusable component, `Card0`, whose body is `depth` frames nested inside one
    /// another before reaching its slot frame; one instance, `Inst0`, fills that slot
    /// with a single leaf rectangle, `Leaf0`.
    private static func deepSlotFill(depth: Int) -> String {
        var tree = #"{"id": "Slot0", "type": "frame", "slot": ["rectangle"], "width": 10, "height": 10}"#
        for level in stride(from: depth - 1, through: 0, by: -1) {
            tree = #"{"id": "F\#(level)", "type": "frame", "children": [\#(tree)]}"#
        }
        let component = #"{"id": "Card0", "type": "frame", "reusable": true, "width": 10, "height": 10, "#
            + #""children": [\#(tree)]}"#
        let instance = #"{"id": "Inst0", "type": "ref", "ref": "Card0", "descendants": {"#
            + #""Slot0": {"children": [{"id": "Leaf0", "type": "rectangle", "width": 4, "height": 4}]}}}"#
        return #"{"version": "2.17", "children": [\#(component), \#(instance)]}"#
    }
}
