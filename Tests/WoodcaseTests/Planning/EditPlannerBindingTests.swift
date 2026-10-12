//
//  EditPlannerBindingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Variable bindings the planner checks on write.
@MainActor
struct EditPlannerBindingTests {
    private func refusal(_ intent: EditIntent, at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: PlannerFixture.document())
    }

    @Test("Binding an undefined variable is refused with undefinedVariable")
    func undefinedBind() throws {
        let refusal = try #require(try refusal(.bind(property: "kind.fills", variable: "nope"), at: "Board/Free"))

        #expect(refusal.code == .undefinedVariable)
        #expect(refusal.property == "kind.fills")
        #expect(refusal.expected == "a $color variable")
    }

    @Test("Writing an undefined $name to a bindable property is refused too")
    func undefinedSet() throws {
        #expect(try refusal(.set(["common.opacity": "$nope"]), at: "Board/Free")?.code == .undefinedVariable)
        #expect(try refusal(.override(["fill": "$nope"]), at: "Board/Chip/Label")?.code == .undefinedVariable)
    }

    @Test("An undefined $name inside a fill object is refused")
    func undefinedNested() throws {
        let fills: AnyCodable = [["type": "color", "color": "$nope"]]
        #expect(try refusal(.set(["kind.fills": fills]), at: "Board/Free")?.code == .undefinedVariable)
    }

    @Test("Binding a variable of the wrong type is refused with variableTypeMismatch")
    func mistypedBind() throws {
        let refusal = try #require(try refusal(.bind(property: "common.opacity", variable: "brand"), at: "Board/Free"))

        #expect(refusal.code == .variableTypeMismatch)
        #expect(refusal.expected == "a $number variable")
        #expect(refusal.message.contains("color"))
    }

    @Test("A mistyped binding written as a value is refused, inside an instance too")
    func mistypedSet() throws {
        #expect(try refusal(.set(["kind.fills": "$spacing"]), at: "Board/Free")?.code == .variableTypeMismatch)
        #expect(try refusal(.override(["content": "$brand"]), at: "Board/Chip/Label")?.code == .variableTypeMismatch)
    }

    @Test("Text content may hold a $word the document does not define")
    func contentLiteral() throws {
        #expect(try refusal(.set(["kind.content": "$30.00"]), at: "Board/Row/Caption") == nil)
        #expect(try refusal(.set(["kind.content": "\\$brand"]), at: "Board/Row/Caption") == nil)
    }

    @Test("Binding content to an undefined variable is still refused")
    func contentBindUndefined() throws {
        #expect(try refusal(.bind(property: "kind.content", variable: "nope"), at: "Board/Row/Caption")?.code
            == .undefinedVariable)
    }

    @Test("Well-typed bindings plan")
    func wellTyped() throws {
        #expect(try refusal(.bind(property: "kind.fills", variable: "ink"), at: "Board/Free") == nil)
        #expect(try refusal(.bind(property: "kind.width", variable: "spacing"), at: "Board/Free") == nil)
        #expect(try refusal(.bind(property: "kind.content", variable: "headline"), at: "Board/Row/Caption") == nil)
        #expect(try refusal(.bind(property: "common.enabled", variable: "visible"), at: "Board/Free") == nil)
    }

    @Test("A variable from an import whose library is not loaded is not refused")
    func unloadedImport() throws {
        let document = try PlannerFixture.document()
        try document.apply(.addImport(EditOperation.AddImport(alias: "lib", path: "./lib.pen")))

        #expect(PlannerFixture.refusal(.set(["kind.fills": "$lib:accent"]), at: "Board/Free", in: document) == nil)
    }
}
