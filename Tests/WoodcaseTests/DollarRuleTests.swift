//
//  DollarRuleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// One rule for a leading `$`, whichever verb wrote the string.
///
/// A `$name` is a variable reference; a `$name` naming a variable the document defines
/// nowhere is the literal it almost certainly was; and `\$` is the escape that says so
/// out loud, anywhere in the string. The three assertions here are that the rule does
/// not change with the route: a `content` written straight onto a text node and the
/// same `content` written into an instance's `descendants` map lint the same and draw
/// the same, forgiveness stops at the properties that are text, and the escape is
/// consumed on both routes.
@MainActor
struct DollarRuleTests {
    // MARK: - Documents

    /// The same price, written as an override on an instance of a component.
    ///
    /// - Parameters:
    ///   - value: The `content` the instance overrides its label with.
    ///   - variables: A `"variables"` member, written whole, or `""` for none.
    /// - Returns: The document as .pen JSON.
    private static func overrideRoute(
        _ value: String,
        variables: String = ""
    ) -> String {
        """
        {
          "version": "2.17",
          "children": [
            {
              "id": "Rt001", "name": "Root", "type": "frame",
              "x": 0, "y": 0, "width": 200, "height": 100, "layout": "none", "fill": "#FFFFFF",
              "children": [
                {
                  "id": "Rf001", "name": "Price", "type": "ref", "ref": "Cmp01",
                  "x": 10, "y": 10,
                  "descendants": { "Lbl01": { "content": "\(value)" } }
                }
              ]
            },
            {
              "id": "Cmp01", "name": "Component", "type": "frame",
              "x": 0, "y": 400, "reusable": true, "layout": "horizontal",
              "width": 60, "height": 24, "fill": "#EEEEEE",
              "children": [
                {
                  "id": "Lbl01", "name": "Label", "type": "text",
                  "width": 40, "height": 20, "content": "placeholder", "fill": "#000000"
                }
              ]
            }
          ]\(variables)
        }
        """
    }

    /// A text node whose content is written straight onto it, for the routes that
    /// only differ in the string.
    ///
    /// - Parameters:
    ///   - value: The `content` to write, as it appears in the .pen JSON.
    ///   - variables: A `"variables"` member, written whole, or `""` for none.
    /// - Returns: The document as .pen JSON.
    private static func contentRoute(
        _ value: String,
        variables: String = ""
    ) -> String {
        """
        {
          "version": "2.17",
          "children": [
            {
              "id": "Rt001", "name": "Root", "type": "frame",
              "x": 0, "y": 0, "width": 200, "height": 100, "layout": "none", "fill": "#FFFFFF",
              "children": [
                {
                  "id": "Txt01", "name": "Price", "type": "text",
                  "width": 80, "height": 20, "content": "\(value)", "fill": "#000000"
                }
              ]
            }
          ]\(variables)
        }
        """
    }

    /// One string variable named `price`, defined for every theme.
    private static let definedPrice = """
    ,
      "variables": { "price": { "type": "string", "value": "£9" } }
    """

    /// A variable named `price` the document defines but nothing can resolve: it and
    /// `list` refer to each other, so the resolver drops both from the table.
    ///
    /// This is the case a themed variable cannot supply — Pen treats the *first*
    /// variant as the default when no theme matches, so a variable "themed away" still
    /// resolves to something. A circular chain is the honest defined-but-unresolvable
    /// name, and the one `resolveTextContent` names in its own comment.
    private static let circularPrice = """
    ,
      "variables": {
        "price": { "type": "string", "value": "$list" },
        "list": { "type": "string", "value": "$price" }
      }
    """

    // MARK: - Helpers

    private func document(_ json: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(json))
    }

    /// Every `unresolved-variable` finding a document raises.
    private func unresolved(_ json: String, theme: [String: String] = [:]) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document(json), theme: theme)
            .filter { $0.check == .unresolvedVariable }
    }

    /// The content the one interesting text node draws with, after expansion and
    /// resolution — the component definition's own `placeholder` label is skipped.
    private func drawnContent(_ json: String, theme: [String: String] = [:]) throws -> PenValue<String>? {
        let settled = try SettledTree(document: document(json), theme: theme)
        let contents = settled.nodes.values.compactMap { node -> PenValue<String>? in
            guard case let .text(data) = node.kind, let content = data.content else { return nil }
            return content == .literal("placeholder") ? nil : content
        }
        #expect(contents.count == 1)
        return contents.first
    }

    /// A `PenValue<String>` through one encode/decode cycle of the .pen wire form.
    private func roundTripped(_ value: PenValue<String>) throws -> (json: String, decoded: PenValue<String>) {
        struct Box: Codable {
            var content: PenValue<String>
        }
        let data = try JSONEncoder().encode(Box(content: value))
        let json = String(decoding: data, as: UTF8.self)
        return try (json, JSONDecoder().decode(Box.self, from: data).content)
    }

    // MARK: - Criterion 1: one string, two routes, one answer

    @Test("A price written as content names no variable and is not a finding")
    func priceAsContentLintsClean() throws {
        #expect(try unresolved(Self.contentRoute("$30.00")).isEmpty)
    }

    @Test("The same price written as an override is not a finding either")
    func priceAsOverrideLintsClean() throws {
        #expect(try unresolved(Self.overrideRoute("$30.00")).isEmpty)
    }

    @Test("The two routes lint identically")
    func bothRoutesLintTheSame() throws {
        let asContent = try unresolved(Self.contentRoute("$30.00"))
        let asOverride = try unresolved(Self.overrideRoute("$30.00"))
        #expect(asContent.map(\.check) == asOverride.map(\.check))
        #expect(asContent.isEmpty)
    }

    @Test("The two routes draw the same literal")
    func bothRoutesDrawTheSame() throws {
        let asContent = try drawnContent(Self.contentRoute("$30.00"))
        let asOverride = try drawnContent(Self.overrideRoute("$30.00"))
        #expect(asContent == .literal("$30.00"))
        #expect(asContent == asOverride)
    }

    // MARK: - Criterion 2: forgiveness did not widen

    @Test("A defined variable written as an override still resolves")
    func definedVariableThroughOverrideResolves() throws {
        let json = Self.overrideRoute("$price", variables: Self.definedPrice)
        #expect(try drawnContent(json) == .literal("£9"))
        #expect(try unresolved(json).isEmpty)
    }

    @Test("A defined variable written as content still resolves")
    func definedVariableAsContentResolves() throws {
        let json = Self.contentRoute("$price", variables: Self.definedPrice)
        #expect(try drawnContent(json) == .literal("£9"))
        #expect(try unresolved(json).isEmpty)
    }

    @Test("A defined name nothing resolves is still unresolved through an override")
    func unresolvableDefinedNameThroughOverrideStillLints() throws {
        let json = Self.overrideRoute("$price", variables: Self.circularPrice)
        let tripped = try unresolved(json)
        #expect(tripped.map(\.nodeID) == ["Rf001"])
        #expect(tripped.first?.message.contains("$price") == true)
    }

    @Test("A defined name nothing resolves is still unresolved in content")
    func unresolvableDefinedNameInContentStillLints() throws {
        let json = Self.contentRoute("$price", variables: Self.circularPrice)
        let tripped = try unresolved(json)
        #expect(tripped.map(\.nodeID) == ["Txt01"])
        #expect(tripped.first?.message.contains("$price") == true)
    }

    @Test("An undefined name in a non-content override is still a dangling reference")
    func undefinedNameInNonContentOverrideStillLints() throws {
        let json = """
        {
          "version": "2.17",
          "children": [
            {
              "id": "Rt001", "name": "Root", "type": "frame",
              "x": 0, "y": 0, "width": 200, "height": 100, "layout": "none", "fill": "#FFFFFF",
              "children": [
                {
                  "id": "Rf001", "name": "Price", "type": "ref", "ref": "Cmp01",
                  "x": 10, "y": 10,
                  "descendants": { "Lbl01": { "fill": "$brnad" } }
                }
              ]
            },
            {
              "id": "Cmp01", "name": "Component", "type": "frame",
              "x": 0, "y": 400, "reusable": true, "layout": "horizontal",
              "width": 60, "height": 24, "fill": "#EEEEEE",
              "children": [
                {
                  "id": "Lbl01", "name": "Label", "type": "text",
                  "width": 40, "height": 20, "content": "placeholder", "fill": "#000000"
                }
              ]
            }
          ]
        }
        """
        let tripped = try unresolved(json)
        #expect(tripped.count == 1)
        #expect(tripped.first?.message.contains("$brnad") == true)
    }

    @Test("An undefined name in a non-content property is still a dangling reference")
    func undefinedNameInNonContentPropertyStillLints() throws {
        let json = Self.contentRoute("hello").replacingOccurrences(
            of: "\"fill\": \"#000000\"", with: "\"fill\": \"$brnad\""
        )
        let tripped = try unresolved(json)
        #expect(tripped.count == 1)
        #expect(tripped.first?.message.contains("$brnad") == true)
    }

    // MARK: - Criterion 3: the escape is consumed anywhere in the string

    @Test("A mid-string escape in content draws a bare dollar")
    func midStringEscapeInContentDrawsDollar() throws {
        // The .pen file holds the two characters `\$`; JSON escapes the backslash.
        let json = Self.contentRoute(#"Price: \\$30"#)
        #expect(try drawnContent(json) == .literal("Price: $30"))
        #expect(try unresolved(json).isEmpty)
    }

    @Test("A mid-string escape in an override draws a bare dollar")
    func midStringEscapeInOverrideDrawsDollar() throws {
        let json = Self.overrideRoute(#"Price: \\$30"#)
        #expect(try drawnContent(json) == .literal("Price: $30"))
        #expect(try unresolved(json).isEmpty)
    }

    @Test("A leading escape still decodes to the literal it names")
    func leadingEscapeDecodesToLiteral() throws {
        let decoded = try JSONDecoder().decode(
            [String: PenValue<String>].self,
            from: Data(#"{"content": "\\$v-muted"}"#.utf8)
        )
        #expect(decoded["content"] == .literal("$v-muted"))
    }

    @Test("A mid-string dollar is written bare, so Pen.app reads it plainly")
    func midStringDollarIsWrittenBare() throws {
        let (json, decoded) = try roundTripped(.literal("Price: $30"))
        #expect(!json.contains("\\\\"))
        #expect(decoded == .literal("Price: $30"))
    }

    @Test("A literal that begins with a dollar round-trips through the escape")
    func leadingDollarRoundTrips() throws {
        let (json, decoded) = try roundTripped(.literal("$30.00"))
        #expect(json.contains("\\\\$30.00"))
        #expect(decoded == .literal("$30.00"))
    }
}
