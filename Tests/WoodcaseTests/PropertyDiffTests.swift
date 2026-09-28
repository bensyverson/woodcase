//
//  PropertyDiffTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct PropertyDiffTests {
    // MARK: - diffCommon

    @Test("Change only name")
    func diffCommonNameOnly() {
        let old = PenNodeCommon(name: "Old")
        let new = PenNodeCommon(name: "New")
        let diff = PropertyDiff.diffCommon(old: old, new: new)
        #expect(diff == Set(["common.name"]))
    }

    @Test("Change multiple common properties")
    func diffCommonMultiple() {
        let old = PenNodeCommon(name: "Old", opacity: .literal(1.0))
        let new = PenNodeCommon(name: "New", opacity: .literal(0.5), reusable: true)
        let diff = PropertyDiff.diffCommon(old: old, new: new)
        #expect(diff.contains("common.name"))
        #expect(diff.contains("common.opacity"))
        #expect(diff.contains("common.reusable"))
    }

    @Test("No changes returns empty set")
    func diffCommonNoChanges() {
        let common = PenNodeCommon(name: "Same", x: .literal(10))
        let diff = PropertyDiff.diffCommon(old: common, new: common)
        #expect(diff.isEmpty)
    }

    @Test("All 13 common properties detected")
    func diffCommonAll13() {
        let old = PenNodeCommon()
        let new = PenNodeCommon(
            name: "Name",
            x: .literal(1),
            y: .literal(2),
            rotation: .literal(45),
            opacity: .literal(0.5),
            enabled: .literal(true),
            flipX: .literal(true),
            flipY: .literal(true),
            reusable: true,
            theme: ["mode": "dark"],
            context: "ctx",
            layoutPosition: .absolute,
            metadata: ["key": AnyCodable("val")]
        )
        let diff = PropertyDiff.diffCommon(old: old, new: new)
        #expect(diff.count == 13)
    }

    // MARK: - diffKind

    @Test("Change width on frame")
    func diffKindFrameWidth() {
        let old = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(100)))
        let new = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(200)))
        let diff = PropertyDiff.diffKind(old: old, new: new)
        #expect(diff == Set(["kind.width"]))
    }

    @Test("Different kind cases returns all keys of both kinds")
    func diffKindDifferentCases() {
        let old = PenNode.Kind.rectangle(PenNode.RectangleData(width: .fixed(100)))
        let new = PenNode.Kind.text(PenNode.TextData(fontSize: .literal(16)))
        let diff = PropertyDiff.diffKind(old: old, new: new)
        // Should return all keys since the kinds are completely different
        #expect(diff.contains("kind.type"))
        #expect(diff.count > 1)
    }

    @Test("Same kind no changes")
    func diffKindNoChanges() {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData(width: .fixed(100)))
        let diff = PropertyDiff.diffKind(old: kind, new: kind)
        #expect(diff.isEmpty)
    }

    @Test("Multiple frame properties changed")
    func diffKindMultipleFrame() {
        let old = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(100), height: .fixed(50)))
        let new = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(200), height: .fixed(100), layout: .horizontal))
        let diff = PropertyDiff.diffKind(old: old, new: new)
        #expect(diff.contains("kind.width"))
        #expect(diff.contains("kind.height"))
        #expect(diff.contains("kind.layout"))
    }

    @Test("Group has no layout properties to diff — only blendMode")
    func diffKindGroupBlendModeOnly() {
        let old = PenNode.Kind.group(PenNode.GroupData(blendMode: .normal))
        let new = PenNode.Kind.group(PenNode.GroupData(blendMode: .multiply))
        let diff = PropertyDiff.diffKind(old: old, new: new)
        #expect(diff == Set(["kind.blendMode"]))
    }

    @Test("allKindKeys for group is only effects and blendMode")
    func allKindKeysGroup() {
        let keys = PropertyDiff.allKindKeys(.group(PenNode.GroupData()))
        #expect(keys == Set(["kind.effects", "kind.blendMode"]))
    }
}
