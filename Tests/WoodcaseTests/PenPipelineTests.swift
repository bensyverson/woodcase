//
//  PenPipelineTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-23.
//

import Foundation
import Testing
@testable import Woodcase

/// Tests for interactions between pipeline stages that can only be caught
/// by running multiple stages together.
struct PenPipelineTests {
    // MARK: - Helpers

    private func makeNode(
        id: String = "node1",
        common: PenNodeCommon = PenNodeCommon(),
        kind: PenNode.Kind
    ) -> PenNode {
        PenNode(id: id, common: common, kind: kind)
    }

    // MARK: - Dollar-Sign Literals Through Ref Expansion

    @Test("Either pipeline order reads a dollar literal in an override the same way")
    func bothPipelineOrdersAgreeOnDollarLiterals() {
        // Resolve-then-expand used to misclassify "$186" as the variable "186": the
        // resolver never looked inside a ref's override map for a content the document
        // defines no variable for, so only expansion-first reached the forgiveness in
        // `resolveTextContent`. The resolver now applies the same rule to an override's
        // own `content`, so the two orders agree.
        let textNode = makeNode(
            id: "price",
            kind: .text(PenNode.TextData(content: .literal("placeholder")))
        )
        let component = makeNode(
            id: "card",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [textNode]))
        )
        let ref = makeNode(
            id: "instance1",
            kind: .ref(PenNode.RefData(
                ref: "card",
                descendants: [
                    "price": PenDescendantOverride(properties: [
                        "content": .string("$186"),
                    ]),
                ]
            ))
        )
        let doc = PenDocument(
            version: "1",
            variables: [
                "accent": PenVariable(type: .color, value: .simple(.string("#C67A52"))),
            ],
            children: [component, ref]
        )

        // The other order: resolve first, then expand
        let resolved = PenVariableResolver.resolve(doc)
        let expanded = PenRefExpander.expand(resolved)

        guard case let .frame(frameData) = expanded.children[0].kind,
              let children = frameData.children,
              case let .text(textData) = children[0].kind,
              let value = textData.content
        else {
            Issue.record("Expected expanded frame with text child")
            return
        }

        #expect(value == .literal("$186"), "Expected literal '$186' but got \(value)")
    }

    @Test("Dollar-prefixed text in ref override is treated as literal, not variable")
    func dollarPrefixedTextInRefOverride() {
        // A reusable component with a text child
        let textNode = makeNode(
            id: "price",
            kind: .text(PenNode.TextData(content: .literal("placeholder")))
        )
        let component = makeNode(
            id: "card",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [textNode]))
        )

        // A ref that overrides the text content to "$186" (a price, not a variable)
        let ref = makeNode(
            id: "instance1",
            kind: .ref(PenNode.RefData(
                ref: "card",
                descendants: [
                    "price": PenDescendantOverride(properties: [
                        "content": .string("$186"),
                    ]),
                ]
            ))
        )

        // Document has a real variable "accent" but NOT "186"
        let doc = PenDocument(
            version: "1",
            variables: [
                "accent": PenVariable(type: .color, value: .simple(.string("#C67A52"))),
            ],
            children: [component, ref]
        )

        // Pipeline: expand refs first, then resolve variables
        let expanded = PenRefExpander.expand(doc)
        let resolved = PenVariableResolver.resolve(expanded)

        // The expanded+resolved tree should have one node (reusable stripped)
        #expect(resolved.children.count == 1)

        // Dig into the expanded frame to find the text node
        guard case let .frame(frameData) = resolved.children[0].kind,
              let children = frameData.children,
              case let .text(textData) = children[0].kind,
              let content = textData.content
        else {
            Issue.record("Expected expanded frame with text child")
            return
        }

        // "$186" should be a literal, not a variable reference
        #expect(content == .literal("$186"), "Expected literal '$186' but got \(content)")
    }

    @Test("Dollar-prefixed text matching a real variable in ref override resolves correctly")
    func dollarPrefixedVariableInRefOverride() {
        // A reusable component with a text child
        let textNode = makeNode(
            id: "label",
            kind: .text(PenNode.TextData(content: .literal("placeholder")))
        )
        let component = makeNode(
            id: "card",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [textNode]))
        )

        // A ref that overrides text to "$greeting" — a real variable
        let ref = makeNode(
            id: "instance1",
            kind: .ref(PenNode.RefData(
                ref: "card",
                descendants: [
                    "label": PenDescendantOverride(properties: [
                        "content": .string("$greeting"),
                    ]),
                ]
            ))
        )

        let doc = PenDocument(
            version: "1",
            variables: [
                "greeting": PenVariable(type: .string, value: .simple(.string("Hello World"))),
            ],
            children: [component, ref]
        )

        // Pipeline: expand refs first, then resolve variables
        let expanded = PenRefExpander.expand(doc)
        let resolved = PenVariableResolver.resolve(expanded)

        guard case let .frame(frameData) = resolved.children[0].kind,
              let children = frameData.children,
              case let .text(textData) = children[0].kind,
              let content = textData.content
        else {
            Issue.record("Expected expanded frame with text child")
            return
        }

        // "$greeting" should resolve to the variable's value
        #expect(content == .literal("Hello World"), "Expected resolved 'Hello World' but got \(content)")
    }
}
