//
//  EditPlannerNestedValueTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The rules the planner holds a value *inside* a structured property to: each nested
/// key's ``PenNestedShape/Field/constraint``, and the type of a `$variable` written
/// there — a gradient stop's position, a fill's opacity, a blur's radius.
@MainActor
struct EditPlannerNestedValueTests {
    private func refusal(_ intent: EditIntent, at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: PlannerFixture.document())
    }

    /// A linear gradient fill whose stops sit at these positions.
    private func gradient(_ positions: [AnyCodable], opacity: AnyCodable? = nil) -> AnyCodable {
        var fill: [String: AnyCodable] = [
            "type": "gradient",
            "gradientType": "linear",
            "colors": .array(positions.map { .dictionary(["color": "#000000", "position": $0]) }),
        ]
        if let opacity { fill["opacity"] = opacity }
        return .array([.dictionary(fill)])
    }

    // MARK: - The schema

    @Test("The nested keys that hold a bounded number carry its constraint")
    func schemaCarriesConstraints() throws {
        let fraction = PenValueConstraint(unit: .fraction, minimum: .inclusive(0), maximum: .inclusive(1))
        let length = PenValueConstraint(unit: .points, minimum: .inclusive(0))
        let stop = try #require(PenFill.stopSchema.variants.first?.fields.first { $0.key == "position" })
        #expect(stop.constraint == fraction)
        let gradient = try #require(PenFill.schema.variants.first { $0.spelling == "gradient" })
        #expect(gradient.fields.first { $0.key == "opacity" }?.constraint == fraction)
        let blur = try #require(PenEffect.schema.variants.first { $0.spelling == "blur" })
        #expect(blur.fields.first { $0.key == "radius" }?.constraint == length)
        let shadow = try #require(PenEffect.schema.variants.first { $0.spelling == "shadow" })
        #expect(shadow.fields.first { $0.key == "blur" }?.constraint == length)
        #expect(PenFill.stopSchema.variants.first?.fields.first { $0.key == "color" }?.constraint == nil)
    }

    // MARK: - Ranges

    @Test("A gradient stop at position 2 is refused with outOfRange, naming where it is")
    func stopPositionOutOfRange() throws {
        let refusal = try #require(try refusal(.set(["kind.fills": gradient([0, 2])]), at: "Board/Free"))

        #expect(refusal.code == .outOfRange)
        #expect(refusal.property == "kind.fills")
        #expect(refusal.expected == "0 to 1, a fraction")
        #expect(refusal.message.contains("kind.fills[0].colors[1].position"))
    }

    @Test("A fill's opacity above 1 is refused, in an array or as one object")
    func fillOpacityOutOfRange() throws {
        #expect(try refusal(.set(["kind.fills": gradient([0, 1], opacity: 1.5)]), at: "Board/Free")?.code
            == .outOfRange)
        let image: AnyCodable = ["type": "image", "url": "a.png", "opacity": -0.1]
        #expect(try refusal(.set(["kind.fills": image]), at: "Board/Free")?.code == .outOfRange)
    }

    @Test("A negative blur radius or shadow blur is refused")
    func negativeBlur() throws {
        let blur: AnyCodable = ["type": "blur", "radius": -4]
        #expect(try refusal(.set(["kind.effects": blur]), at: "Board/Free")?.code == .outOfRange)
        let shadow: AnyCodable = [["type": "shadow", "blur": -1, "color": "#000000"]]
        #expect(try refusal(.set(["kind.effects": shadow]), at: "Board/Free")?.code == .outOfRange)
    }

    @Test("An override inside an instance is held to the same nested rules")
    func overrideNestedOutOfRange() throws {
        #expect(try refusal(.override(["fill": gradient([0, 2])]), at: "Board/Chip/Label")?.code == .outOfRange)
    }

    @Test("Nested values inside their ranges plan")
    func nestedInRange() throws {
        #expect(try refusal(.set(["kind.fills": gradient([0, 0.5, 1], opacity: 0.5)]), at: "Board/Free") == nil)
        let effects: AnyCodable = [["type": "blur", "radius": 0], ["type": "shadow", "blur": 8, "color": "#000000"]]
        #expect(try refusal(.set(["kind.effects": effects]), at: "Board/Free") == nil)
        // Just past the edge of each is not.
        #expect(try refusal(.set(["kind.fills": gradient([0, 1.0001])]), at: "Board/Free") != nil)
        let below: AnyCodable = [["type": "blur", "radius": -0.0001]]
        #expect(try refusal(.set(["kind.effects": below]), at: "Board/Free") != nil)
    }

    // MARK: - Variable types

    @Test("A nested variable of the wrong type is refused with variableTypeMismatch")
    func nestedVariableWrongType() throws {
        let color: AnyCodable = [["type": "color", "color": "$spacing"]]
        let refused = try #require(try refusal(.set(["kind.fills": color]), at: "Board/Free"))
        #expect(refused.code == .variableTypeMismatch)
        #expect(refused.expected == "a $color variable")
        #expect(try refusal(.set(["kind.fills": gradient(["$brand"])]), at: "Board/Free")?.code
            == .variableTypeMismatch)
        let shadow: AnyCodable = [["type": "shadow", "blur": 4, "color": "$spacing"]]
        #expect(try refusal(.set(["kind.effects": shadow]), at: "Board/Free")?.code == .variableTypeMismatch)
    }

    @Test("A nested variable of the right type plans")
    func nestedVariableRightType() throws {
        let color: AnyCodable = [["type": "color", "color": "$brand"]]
        #expect(try refusal(.set(["kind.fills": color]), at: "Board/Free") == nil)
        #expect(try refusal(.set(["kind.fills": gradient(["$spacing", 1])]), at: "Board/Free") == nil)
        // The same keys bound to a variable of the other type are not.
        let swapped: AnyCodable = [["type": "color", "color": "$spacing"]]
        #expect(try refusal(.set(["kind.fills": swapped]), at: "Board/Free") != nil)
        #expect(try refusal(.set(["kind.fills": gradient(["$brand", 1])]), at: "Board/Free") != nil)
    }

    // MARK: - Values the write leaves as they were

    /// The fixture with `Board/Free`'s fills stored without planning, as a file may hold them.
    private func document(holdingFills fills: AnyCodable) throws -> EditableDocument {
        let document = try PlannerFixture.document()
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "Fre01", properties: ["kind.fills": fills])))
        return document
    }

    @Test("An out-of-range stop the file already holds lets an edit to another stop through")
    func untouchedOutOfRangeStopPasses() throws {
        let document = try document(holdingFills: gradient([0, 2]))

        #expect(PlannerFixture.refusal(.set(["kind.fills": gradient([0.5, 2])]), at: "Board/Free", in: document) == nil)
        let refused = PlannerFixture.refusal(.set(["kind.fills": gradient([0, 3])]), at: "Board/Free", in: document)
        #expect(refused?.code == .outOfRange)
        #expect(refused?.message.contains("kind.fills[0].colors[1].position") == true)
    }

    @Test("A wrong-typed nested variable the file already holds lets an edit to another fill through")
    func untouchedWrongVariablePasses() throws {
        let document = try document(holdingFills: [
            ["type": "color", "color": "$spacing"], ["type": "color", "color": "#000000"],
        ])

        let other: AnyCodable = [["type": "color", "color": "$spacing"], ["type": "color", "color": "#FFFFFF"]]
        #expect(PlannerFixture.refusal(.set(["kind.fills": other]), at: "Board/Free", in: document) == nil)
        let changed: AnyCodable = [["type": "color", "color": "$headline"], ["type": "color", "color": "#000000"]]
        #expect(PlannerFixture.refusal(.set(["kind.fills": changed]), at: "Board/Free", in: document)?.code
            == .variableTypeMismatch)
    }
}
