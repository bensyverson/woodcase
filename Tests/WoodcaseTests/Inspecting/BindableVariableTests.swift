//
//  BindableVariableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `bindableVariables(for:at:)`: the variables an inspector offers for a property —
/// only those of the type it takes, each with its value where the node draws.
@MainActor
struct BindableVariableTests {
    private func names(_ property: String, at raw: String, in document: EditableDocument) throws -> [String] {
        try document.bindableVariables(for: property, at: document.resolve(raw)).map(\.name)
    }

    // MARK: - By type

    @Test("Only color variables are offered for a fill")
    func colorsForAFill() throws {
        let document = try PlannerFixture.document()
        let offered = try document.bindableVariables(for: "kind.fills", at: document.resolve("Board/Free"))

        #expect(offered.map(\.name) == ["brand", "ink"])
        #expect(offered.allSatisfy { $0.type == .color })
        #expect(offered.allSatisfy { $0.origin == .document })
        #expect(offered.first?.reference == "$brand")
    }

    @Test("Each property is offered the variables of its own type")
    func eachTypeItsOwn() throws {
        let document = try PlannerFixture.document()
        #expect(try names("common.opacity", at: "Board/Free", in: document) == ["spacing"])
        #expect(try names("common.enabled", at: "Board/Free", in: document) == ["visible"])
        #expect(try names("kind.content", at: "Board/Row/Caption", in: document) == ["headline"])
    }

    @Test("A raw key is offered the same variables as its path")
    func rawKey() throws {
        let document = try PlannerFixture.document()
        #expect(try names("fill", at: "Board/Free", in: document) == ["brand", "ink"])
    }

    @Test("A property that takes no variable, or that is no property, is offered none")
    func noneOffered() throws {
        let document = try PlannerFixture.document()
        #expect(try names("common.name", at: "Board/Free", in: document).isEmpty)
        #expect(try names("kind.nonsense", at: "Board/Free", in: document).isEmpty)
    }

    @Test("A node inside an instance is offered variables too")
    func instanceDescendant() throws {
        let document = try PlannerFixture.document()
        #expect(try names("kind.fills", at: "Board/Chip/Label", in: document) == ["brand", "ink"])
    }

    // MARK: - By variable type

    @Test("bindableVariables(ofType:at:) lists the color variables for a node")
    func colorsByType() throws {
        let document = try PlannerFixture.document()
        let free = try document.resolve("Board/Free")
        let colors = document.bindableVariables(ofType: .color, at: free)

        #expect(colors.map(\.name) == ["brand", "ink"])
        #expect(colors == document.bindableVariables(for: "kind.fills", at: free))
        #expect(colors.last?.value == "#111111")
    }

    @Test("Each variable type lists its own variables, wherever the node is")
    func eachTypeByType() throws {
        let document = try PlannerFixture.document()
        let label = try document.resolve("Board/Chip/Label")
        #expect(document.bindableVariables(ofType: .number, at: label).map(\.name) == ["spacing"])
        #expect(document.bindableVariables(ofType: .boolean, at: label).map(\.name) == ["visible"])
        #expect(document.bindableVariables(ofType: .string, at: label).map(\.name) == ["headline"])
    }

    // MARK: - Values

    @Test("A themed variable's value is the one under the theme the node draws with")
    func themedValue() throws {
        let document = try PlannerFixture.document()
        let free = try document.resolve("Board/Free")
        #expect(document.bindableVariables(for: "kind.fills", at: free).last?.value == "#111111")

        try InspectionFixture.write(.set(["common.theme": .dictionary(["mode": "dark"])]),
                                    at: document.resolve("Board"), in: document)

        #expect(document.bindableVariables(for: "kind.fills", at: free).last?.value == "#EEEEEE")
    }

    // MARK: - Agreement with the planner

    @Test("Every offered variable binds, and a variable of another type is refused")
    func agreesWithThePlanner() throws {
        let document = try PlannerFixture.document()
        let target = try document.resolve("Board/Free")
        for variable in document.bindableVariables(for: "kind.fills", at: target) {
            _ = try EditPlanner.plan(.bind(property: "kind.fills", variable: variable.name), at: target, in: document)
        }
        #expect(PlannerFixture.refusal(.bind(property: "kind.fills", variable: "spacing"), at: "Board/Free", in: document)?
            .code == .variableTypeMismatch)
    }

    // MARK: - Libraries

    @Test("A variable a library defines is offered with its alias")
    func libraryVariable() throws {
        let document = try InspectionFixture.libraryDocument()
        let offered = document.bindableVariables(for: "kind.fills", at: .node(id: "Art01"))

        let accent = try #require(offered.first { $0.name == "K:accent" })
        #expect(accent.origin == .library(alias: "K"))
        #expect(accent.type == .color)
        #expect(accent.value == "#FF6600")
    }
}
