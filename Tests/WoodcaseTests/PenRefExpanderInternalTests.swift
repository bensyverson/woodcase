//
//  PenRefExpanderInternalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct PenRefExpanderInternalTests {
    // MARK: - buildRegistry

    @Test("buildRegistry finds reusable nodes")
    func buildRegistryFindsReusables() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "label", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))
        )
        let regular = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData())
        )
        let registry = PenRefExpander.buildRegistry(from: [component, regular])

        #expect(registry.count == 1)
        #expect(registry["comp1"] != nil)
        #expect(registry["rect1"] == nil)
    }

    // MARK: - expandRef

    @Test("expandRef expands a simple ref node")
    func expandRefSimple() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "label", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(x: .literal(100)),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let registry = ["comp1": component]
        let expanded = PenRefExpander.expandRef(
            refNode: refNode,
            registry: registry,
            visited: []
        )

        // Should be a frame, not a ref
        if case .frame = expanded.kind {
            // ID should be prefixed
            #expect(expanded.id == "ref1/comp1")
        } else {
            Issue.record("Expected expanded node to be a frame")
        }
    }

    // MARK: - prefixIDs

    @Test("prefixIDs prefixes all node IDs")
    func prefixIDsWorks() {
        let node = PenNode(
            id: "root",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "child", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))
        )
        let prefixed = PenRefExpander.prefixIDs(in: node, prefix: "ref1")

        #expect(prefixed.id == "ref1/root")
        if case let .frame(data) = prefixed.kind {
            #expect(data.children?.first?.id == "ref1/child")
        } else {
            Issue.record("Expected frame kind")
        }
    }

    // MARK: - transferCommonProperties

    @Test("transferCommonProperties transfers positional properties")
    func transferCommonPropsWorks() {
        let refCommon = PenNodeCommon(name: "Instance", x: .literal(50), y: .literal(100))
        let componentCommon = PenNodeCommon(name: "Component", x: .literal(0), y: .literal(0), reusable: true)
        let result = PenRefExpander.transferCommonProperties(from: refCommon, to: componentCommon)

        #expect(result.name == "Instance")
        #expect(result.x == .literal(50))
        #expect(result.y == .literal(100))
        #expect(result.reusable == nil) // Should not transfer reusable
    }
}
