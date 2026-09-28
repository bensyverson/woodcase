//
//  PenRefExpanderTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-22.
//

import Foundation
import Testing
import Woodcase

struct PenRefExpanderTests {
    // MARK: - Helpers

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func loadFixture(_ name: String) throws -> PenDocument {
        let url = fixtureURL(name)
        return try PenParser.parse(contentsOf: url)
    }

    private func makeNode(
        id: String = "node1",
        common: PenNodeCommon = PenNodeCommon(),
        kind: PenNode.Kind
    ) -> PenNode {
        PenNode(id: id, common: common, kind: kind)
    }

    // MARK: - Simple Expansion

    @Test("Simple ref expands to cloned component tree")
    func simpleRefExpansion() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // Reusable component should be removed, two ref instances expanded
        // Original: 3 children (1 reusable + 2 refs)
        // Expanded: 2 children (both expanded from component)
        #expect(expanded.children.count == 2)
    }

    @Test("Expanded node has correct type from component")
    func expandedNodeHasCorrectType() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // Both expanded nodes should be frames (the component is a frame)
        for child in expanded.children {
            if case .frame = child.kind {
                // Good
            } else {
                Issue.record("Expected frame kind, got \(child.kind)")
            }
        }
    }

    @Test("Expanded node inherits ref node's position")
    func expandedNodeInheritsRefPosition() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // card-instance1 has x: 0, y: 0
        let inst1 = expanded.children[0]
        #expect(inst1.common.x == .literal(0))
        #expect(inst1.common.y == .literal(0))

        // card-instance2 has x: 320, y: 0
        let inst2 = expanded.children[1]
        #expect(inst2.common.x == .literal(320))
        #expect(inst2.common.y == .literal(0))
    }

    @Test("Expanded node root ID is prefixed with ref node ID")
    func expandedNodeIDIsPrefixed() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        #expect(expanded.children[0].id == "card-instance1/card-component")
        #expect(expanded.children[1].id == "card-instance2/card-component")
    }

    @Test("Expanded child IDs carry the prefix")
    func expandedChildIDsArePrefixed() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        if case let .frame(data) = expanded.children[0].kind,
           let children = data.children
        {
            #expect(children[0].id == "card-instance1/card-title")
            #expect(children[1].id == "card-instance1/card-body")
        } else {
            Issue.record("Expected frame with children")
        }
    }

    // MARK: - Descendant Overrides

    @Test("Descendant property override patches text content")
    func descendantPropertyOverride() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // card-instance1 overrides card-title content to "Custom Title"
        if case let .frame(data) = expanded.children[0].kind,
           let children = data.children,
           case let .text(titleData) = children[0].kind,
           let content = titleData.content
        {
            #expect(content == .literal("Custom Title"))
        } else {
            Issue.record("Expected overridden text content")
        }
    }

    @Test("Descendant multi-property override patches content and fontSize")
    func descendantMultiPropertyOverride() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // card-instance1 overrides card-body: content + fontSize
        if case let .frame(data) = expanded.children[0].kind,
           let children = data.children,
           case let .text(bodyData) = children[1].kind
        {
            if let content = bodyData.content {
                #expect(content == .literal("Overridden body text"))
            }
            #expect(bodyData.fontSize == .literal(16))
        } else {
            Issue.record("Expected multi-property override")
        }
    }

    @Test("Descendant enabled override disables a node")
    func descendantEnabledOverride() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // card-instance2 overrides card-title: enabled = false
        if case let .frame(data) = expanded.children[1].kind,
           let children = data.children
        {
            #expect(children[0].common.enabled == .literal(false))
        } else {
            Issue.record("Expected enabled override")
        }
    }

    // MARK: - Multiple Instances

    @Test("Multiple instances of same component produce distinct ID-prefixed trees")
    func multipleInstancesOfSameComponent() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // Two instances should have different ID prefixes
        let ids1 = collectIDs(expanded.children[0])
        let ids2 = collectIDs(expanded.children[1])

        // No overlap
        let overlap = ids1.intersection(ids2)
        #expect(overlap.isEmpty, "Instance IDs should not overlap: \(overlap)")

        // Both should have same structure
        #expect(ids1.count == ids2.count)
    }

    private func collectIDs(_ node: PenNode) -> Set<String> {
        var ids: Set<String> = [node.id]
        if let children = nodeChildren(node) {
            for child in children {
                ids.formUnion(collectIDs(child))
            }
        }
        return ids
    }

    private func nodeChildren(_ node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(d): d.children
        case let .group(d): d.children
        default: nil
        }
    }

    // MARK: - Reusable Stripping

    @Test("Reusable nodes are removed from output")
    func reusableNodesRemovedFromOutput() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // No nodes should have reusable: true
        for node in expanded.children {
            #expect(node.common.reusable != true, "Reusable node should be stripped: \(node.id)")
        }
    }

    // MARK: - Nested Refs

    @Test("Nested ref expansion works correctly")
    func nestedRefExpansion() throws {
        let doc = try loadFixture("expander-nested-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // Original: badge (reusable), button (reusable, contains ref to badge), nav-button (ref to button)
        // Expanded: just nav-button, fully expanded

        // Should have 1 child (nav-button expanded)
        #expect(expanded.children.count == 1)

        let navButton = expanded.children[0]
        // Should be a frame (button component)
        if case let .frame(data) = navButton.kind,
           let children = data.children
        {
            // Button has: button-label (text) and button-badge (was ref to badge, now expanded frame)
            #expect(children.count == 2)

            // The nested badge ref should be expanded to a frame
            let badge = children[1]
            if case let .frame(badgeData) = badge.kind,
               let badgeChildren = badgeData.children
            {
                // badge-label should exist with overridden content "!"
                if case let .text(labelData) = badgeChildren[0].kind,
                   let content = labelData.content
                {
                    #expect(content == .literal("!"))
                } else {
                    Issue.record("Expected badge label text")
                }
            } else {
                Issue.record("Expected expanded badge frame")
            }
        } else {
            Issue.record("Expected nav-button as frame")
        }
    }

    // MARK: - Edge Cases

    @Test("Missing ref target leaves node unchanged")
    func missingRefTargetHandledGracefully() {
        let refNode = makeNode(
            id: "bad-ref",
            kind: .ref(PenNode.RefData(ref: "nonexistent"))
        )
        let doc = PenDocument(version: "1", children: [refNode])

        let expanded = PenRefExpander.expand(doc)
        // The ref node should be removed or left as-is
        // Since we can't expand it and it's not reusable, it stays
        #expect(expanded.children.count == 1)
        if case .ref = expanded.children[0].kind {
            // Left as ref — acceptable
        } else {
            Issue.record("Expected ref to remain when target is missing")
        }
    }

    @Test("Circular ref protection prevents infinite loop")
    func circularRefProtection() {
        // Component A refs component B, component B refs component A
        let compA = PenNode(
            id: "compA",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(
                    id: "ref-to-b",
                    common: PenNodeCommon(),
                    kind: .ref(PenNode.RefData(ref: "compB"))
                ),
            ]))
        )
        let compB = PenNode(
            id: "compB",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(
                    id: "ref-to-a",
                    common: PenNodeCommon(),
                    kind: .ref(PenNode.RefData(ref: "compA"))
                ),
            ]))
        )
        let usage = PenNode(
            id: "use-a",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "compA"))
        )
        let doc = PenDocument(version: "1", children: [compA, compB, usage])

        // Should not hang
        let expanded = PenRefExpander.expand(doc)
        // Should produce some output without crashing
        #expect(expanded.children.count >= 1)
    }

    @Test("Document with no refs returns unchanged minus reusable stripping")
    func documentWithNoRefsReturnsUnchanged() {
        let doc = PenDocument(version: "1", children: [
            makeNode(id: "rect1", kind: .rectangle(PenNode.RectangleData())),
            makeNode(id: "rect2", kind: .rectangle(PenNode.RectangleData())),
        ])

        let expanded = PenRefExpander.expand(doc)
        #expect(expanded.children.count == 2)
        #expect(expanded.children[0].id == "rect1")
        #expect(expanded.children[1].id == "rect2")
    }

    @Test("Ref node name is preserved on expanded node")
    func refNamePreservation() {
        let component = PenNode(
            id: "comp",
            common: PenNodeCommon(name: "Component", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Custom Name"),
            kind: .ref(PenNode.RefData(ref: "comp"))
        )
        let doc = PenDocument(version: "1", children: [component, ref])

        let expanded = PenRefExpander.expand(doc)
        #expect(expanded.children.count == 1)
        // Ref node's name should take precedence
        #expect(expanded.children[0].common.name == "Custom Name")
    }

    @Test("Override only affects matching descendant, not siblings")
    func overrideOnlyAffectsMatchingDescendant() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        // card-instance2 overrides card-title (enabled: false)
        // card-body should NOT be affected
        if case let .frame(data) = expanded.children[1].kind,
           let children = data.children,
           case let .text(bodyData) = children[1].kind,
           let content = bodyData.content
        {
            // Body should have default content
            #expect(content == .literal("Default body text"))
        } else {
            Issue.record("Expected unaffected sibling")
        }
    }

    @Test("Expanded node inherits component width and height")
    func expandedNodeInheritsComponentDimensions() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        let expanded = PenRefExpander.expand(doc)

        if case let .frame(data) = expanded.children[0].kind {
            #expect(data.width == .fixed(300))
            #expect(data.height == .fixed(200))
        } else {
            Issue.record("Expected frame with component dimensions")
        }
    }

    // MARK: - Root Overrides

    @Test("Ref node root overrides are applied to expanded component root")
    func rootOverridesApplied() {
        // A reusable component with fixed width
        let component = PenNode(
            id: "card",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(width: .fixed(120), height: .fixed(80)))
        )

        // A ref that overrides width and height on the root
        let ref = PenNode(
            id: "instance1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(
                ref: "card",
                rootOverrides: [
                    "width": .string("fill_container"),
                    "height": .string("fit_content"),
                ]
            ))
        )
        let doc = PenDocument(version: "1", children: [component, ref])
        let expanded = PenRefExpander.expand(doc)

        #expect(expanded.children.count == 1)
        guard case let .frame(data) = expanded.children[0].kind else {
            Issue.record("Expected expanded frame")
            return
        }
        #expect(data.width == .fillContainer(fallback: nil), "Root override should change width to fill_container")
        #expect(data.height == .fitContent(fallback: nil), "Root override should change height to fit_content")
    }

    @Test("Ref node root overrides combine with descendant overrides")
    func rootAndDescendantOverrides() {
        let textNode = PenNode(
            id: "label",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(content: .literal("default")))
        )
        let component = PenNode(
            id: "card",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(
                width: .fixed(100),
                fills: .single(.shorthand("#000000")),
                children: [textNode]
            ))
        )

        let ref = PenNode(
            id: "inst",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(
                ref: "card",
                descendants: [
                    "label": PenDescendantOverride(properties: [
                        "content": .string("overridden"),
                    ]),
                ],
                rootOverrides: [
                    "fill": .string("#FF0000"),
                    "width": .string("fill_container"),
                ]
            ))
        )
        let doc = PenDocument(version: "1", children: [component, ref])
        let expanded = PenRefExpander.expand(doc)

        #expect(expanded.children.count == 1)
        guard case let .frame(data) = expanded.children[0].kind else {
            Issue.record("Expected expanded frame")
            return
        }
        // Root overrides applied
        #expect(data.width == .fillContainer(fallback: nil))
        #expect(data.fills == .single(.shorthand("#FF0000")))
        // Descendant override also applied
        if let children = data.children,
           case let .text(textData) = children[0].kind
        {
            let expected: PenValue<String> = .literal("overridden")
            #expect(textData.content == expected)
        } else {
            Issue.record("Expected text child with overridden content")
        }
    }
}
