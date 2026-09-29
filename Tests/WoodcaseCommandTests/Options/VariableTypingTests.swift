//
//  VariableTypingTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

struct VariableTypingTests {
    // MARK: - The name=value argument

    @Test("An assignment splits on the first equals sign")
    func splitsOnFirstEquals() {
        let assignment = VariableAssignment(argument: "brand=#FF6600")
        #expect(assignment?.name == "brand")
        #expect(assignment?.literal == "#FF6600")
    }

    @Test("A value may itself contain equals signs")
    func keepsLaterEqualsSigns() {
        let assignment = VariableAssignment(argument: "query=a=b&c=d")
        #expect(assignment?.name == "query")
        #expect(assignment?.literal == "a=b&c=d")
    }

    @Test("An empty value is a legal empty string")
    func allowsEmptyValue() {
        let assignment = VariableAssignment(argument: "blank=")
        #expect(assignment?.name == "blank")
        #expect(assignment?.literal == "")
    }

    @Test("A missing equals sign is not an assignment")
    func rejectsMissingEquals() {
        #expect(VariableAssignment(argument: "brand") == nil)
    }

    @Test("An empty name is not an assignment")
    func rejectsEmptyName() {
        #expect(VariableAssignment(argument: "=#FF6600") == nil)
    }

    @Test("A name carrying a colon is not an assignment")
    func rejectsColonInName() {
        // The 2.17 schema's key pattern for a variable name is `[^:]+`.
        #expect(VariableAssignment(argument: "a:b=1") == nil)
    }

    // MARK: - Inference

    @Test(
        "A hex literal in any of the schema's three widths reads as a color",
        arguments: ["#fff", "#FF6600", "#FF6600AA", "#ABCDEF"]
    )
    func infersColor(literal: String) {
        #expect(VariableTyping.inferredType(of: literal) == .color)
    }

    @Test(
        "Something hex-shaped but not a hex color reads as a string",
        arguments: ["#GGG", "#FF66", "#", "FF6600", "rgba(0,0,0,0.5)"]
    )
    func doesNotInferColor(literal: String) {
        #expect(VariableTyping.inferredType(of: literal) == .string)
    }

    @Test("true and false read as booleans", arguments: ["true", "false"])
    func infersBoolean(literal: String) {
        #expect(VariableTyping.inferredType(of: literal) == .boolean)
    }

    @Test("A numeric literal reads as a number", arguments: ["16", "-2.5", "0", "1e3"])
    func infersNumber(literal: String) {
        #expect(VariableTyping.inferredType(of: literal) == .number)
    }

    @Test("Anything else reads as a string", arguments: ["Breaking News", "", "16pt"])
    func infersString(literal: String) {
        #expect(VariableTyping.inferredType(of: literal) == .string)
    }

    @Test("A $reference has no inferable type of its own")
    func referenceHasNoInferredType() {
        #expect(VariableTyping.inferredType(of: "$brand") == nil)
    }

    // MARK: - Validation against a declared type

    @Test("An integral number is stored as an integer, so a file round-trips unchanged")
    func storesIntegralNumbersAsIntegers() {
        #expect(VariableTyping.value(of: "16", as: .number) == .int(16))
        #expect(VariableTyping.value(of: "-2.5", as: .number) == .double(-2.5))
    }

    @Test("A boolean is stored as a boolean")
    func storesBooleans() {
        #expect(VariableTyping.value(of: "true", as: .boolean) == .bool(true))
        #expect(VariableTyping.value(of: "false", as: .boolean) == .bool(false))
    }

    @Test("A color is stored verbatim")
    func storesColors() {
        #expect(VariableTyping.value(of: "#FF6600", as: .color) == .string("#FF6600"))
    }

    @Test("A declared string type takes a literal that would have inferred as something else")
    func stringTypeTakesAnyLiteral() {
        #expect(VariableTyping.value(of: "16", as: .string) == .string("16"))
        #expect(VariableTyping.value(of: "#FF6600", as: .string) == .string("#FF6600"))
    }

    @Test("A literal that is not of the declared type is refused")
    func refusesMismatchedLiteral() {
        #expect(VariableTyping.value(of: "Breaking News", as: .number) == nil)
        #expect(VariableTyping.value(of: "16", as: .boolean) == nil)
        #expect(VariableTyping.value(of: "reddish", as: .color) == nil)
    }

    @Test("A $reference is a legal value for every type")
    func referenceIsLegalEverywhere() {
        for type in [PenVariableType.color, .number, .string, .boolean] {
            #expect(VariableTyping.value(of: "$brand", as: type) == .string("$brand"))
        }
    }
}
