//
//  EditPlannerDefaultTextStyleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Use as Default Text Style: marking one text as the document's default unmarks every
/// other, in one edit; choosing it again on the default unmarks it (Penumbra spec §6.3).
@MainActor
struct EditPlannerDefaultTextStyleTests {
    // MARK: - Mark

    @Test("Marking a text marks it")
    func marks() throws {
        let document = try DefaultTextStyleFixture.document()
        let operations = try EditPlanner.planMarkDefaultTextStyle(nodeID: "Body", in: document)
        try DefaultTextStyleFixture.apply(operations, to: document)
        #expect(DefaultTextStyleFixture.marked(in: document) == ["Body"])
    }

    @Test("Marking a text unmarks every other marked text, in the same edit")
    func unmarksOthers() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Title", "Label"], in: document)
        let operations = try EditPlanner.planMarkDefaultTextStyle(nodeID: "Body", in: document)
        #expect(DefaultTextStyleFixture.written(by: operations) == ["Title", "Label", "Body"])
        try DefaultTextStyleFixture.apply(operations, to: document)
        #expect(DefaultTextStyleFixture.marked(in: document) == ["Body"])
        #expect(document.node(id: "Title")?.common.metadata?[woodcase: .defaultTextStyle] == nil)
    }

    @Test("Marking the text already marked alone writes nothing")
    func alreadyMarked() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        #expect(try EditPlanner.planMarkDefaultTextStyle(nodeID: "Body", in: document).isEmpty)
    }

    @Test("Marking and unmarking keep every other metadata key")
    func keepsOtherMetadata() throws {
        let document = try DefaultTextStyleFixture.document()
        let role = PenMetadata.WoodcaseKey.role.propertyPath
        for id in ["Title", "Body"] {
            let plan = try EditPlanner.plan(.set([role: "heading"]), at: PlannerFixture.address("#\(id)"), in: document)
            try DefaultTextStyleFixture.apply(plan.operations, to: document)
        }
        try DefaultTextStyleFixture.write(true, on: ["Title"], in: document)
        try DefaultTextStyleFixture.apply(
            EditPlanner.planMarkDefaultTextStyle(nodeID: "Body", in: document), to: document
        )
        #expect(document.node(id: "Title")?.common.metadata?[woodcase: .role] == .string("heading"))
        #expect(document.node(id: "Body")?.common.metadata?[woodcase: .role] == .string("heading"))
        try DefaultTextStyleFixture.apply(EditPlanner.planUnmarkDefaultTextStyle(in: document), to: document)
        #expect(document.node(id: "Body")?.common.metadata?[woodcase: .role] == .string("heading"))
        #expect(DefaultTextStyleFixture.marked(in: document).isEmpty)
    }

    // MARK: - Unmark

    @Test("Unmarking removes the mark from every marked text")
    func unmarksAll() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Body", "Deep"], in: document)
        let operations = EditPlanner.planUnmarkDefaultTextStyle(in: document)
        #expect(DefaultTextStyleFixture.written(by: operations) == ["Body", "Deep"])
        try DefaultTextStyleFixture.apply(operations, to: document)
        #expect(DefaultTextStyleFixture.marked(in: document).isEmpty)
        #expect(document.defaultTextStyleNodeID() == nil)
    }

    @Test("Unmarking with nothing marked writes nothing")
    func unmarkNothing() throws {
        let document = try DefaultTextStyleFixture.document()
        #expect(EditPlanner.planUnmarkDefaultTextStyle(in: document).isEmpty)
    }

    // MARK: - Refusals

    @Test("A node that is not a text is refused with notAText", arguments: ["Shape", "Page", "Sticky", "Chip"])
    func notAText(id: String) throws {
        let document = try DefaultTextStyleFixture.document()
        #expect(DefaultTextStyleFixture.markRefusal(id, in: document)?.code == .notAText)
    }

    @Test("A text inside an instance is refused with insideInstance")
    func insideInstance() throws {
        let document = try DefaultTextStyleFixture.document()
        let inside = document.expandedID(of: .instanceDescendant(refID: "Chip", descendantKey: "Label"))
        #expect(DefaultTextStyleFixture.markRefusal(inside, in: document)?.code == .insideInstance)
    }

    @Test("An id naming nothing is refused with addressNotFound")
    func notFound() throws {
        let document = try DefaultTextStyleFixture.document()
        #expect(DefaultTextStyleFixture.markRefusal("Nope", in: document)?.code == .addressNotFound)
    }
}
