//
//  DefaultTextStyleQueryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What an editor reads the default text style from: the marked text, and the first
/// font-family variable (Penumbra spec §6.3, Ben's ruling of 2026-10-18).
@MainActor
struct DefaultTextStyleQueryTests {
    // MARK: - The marked text

    @Test("No marked text is no default")
    func noneMarked() throws {
        let document = try DefaultTextStyleFixture.document()
        #expect(document.defaultTextStyleNodeID() == nil)
    }

    @Test("The marked text is the default")
    func oneMarked() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        #expect(document.defaultTextStyleNodeID() == "Body")
    }

    @Test("Of two marks, the first in document order wins: depth first, before a later sibling")
    func depthFirst() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Body", "Deep"], in: document)
        #expect(document.defaultTextStyleNodeID() == "Deep")
    }

    @Test("Of two marks, an earlier root's wins over a later root's")
    func rootOrder() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Label", "Body"], in: document)
        #expect(document.defaultTextStyleNodeID() == "Body")
    }

    @Test("A text in a component's definition may be the default")
    func inComponent() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Label"], in: document)
        #expect(document.defaultTextStyleNodeID() == "Label")
    }

    @Test("A mark on a node that is not a text, or a false mark, is no default")
    func ignoredMarks() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Page", "Shape"], in: document)
        try DefaultTextStyleFixture.write(false, on: ["Title"], in: document)
        #expect(document.defaultTextStyleNodeID() == nil)
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        #expect(document.defaultTextStyleNodeID() == "Body")
    }

    // MARK: - The first font-family variable

    @Test("The first string variable some text binds as its family, by variable order")
    func firstBound() throws {
        let document = try DefaultTextStyleFixture.document()
        // `aaa` is bound only by a note, `abc` is a number, `brandFont` is bound by nothing.
        #expect(document.firstFontFamilyVariableName() == "body")
    }

    @Test("A variable bound by no text is never chosen, whatever its name or value")
    func unboundIgnored() throws {
        let document = try DefaultTextStyleFixture.document()
        let plan = try EditPlanner.plan(.unbind(property: "kind.fontFamily"), at: PlannerFixture.address("#Body"),
                                        in: document)
        try DefaultTextStyleFixture.apply(plan.operations, to: document)
        #expect(document.firstFontFamilyVariableName() == "display")
        let title = try EditPlanner.plan(.unbind(property: "kind.fontFamily"), at: PlannerFixture.address("#Title"),
                                         in: document)
        try DefaultTextStyleFixture.apply(title.operations, to: document)
        #expect(document.firstFontFamilyVariableName() == nil)
    }

    @Test("No variables is no font-family variable")
    func noVariables() throws {
        let document = try DefaultTextStyleFixture.document()
        document.variables = nil
        #expect(document.firstFontFamilyVariableName() == nil)
    }
}
