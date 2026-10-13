//
//  EditPlannerNestedLocationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The typed location a refusal of a value *inside* a structured property carries
/// (``EditRefusal/nested``), so an inspector can place it under the right layer without
/// parsing the sentence.
@MainActor
struct EditPlannerNestedLocationTests {
    private func refusal(_ intent: EditIntent, at raw: String = "Board/Free") throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: PlannerFixture.document())
    }

    private func stops(_ positions: [AnyCodable]) -> AnyCodable {
        .dictionary([
            "type": "gradient", "gradientType": "linear",
            "colors": .array(positions.map { .dictionary(["color": "#000000", "position": $0]) }),
        ])
    }

    @Test("A stop out of range names its layer index and its keys")
    func stopOutOfRange() throws {
        let layers: AnyCodable = [["type": "color", "color": "#FF0000"], stops([0, 2])]
        let refusal = try #require(try refusal(.set(["kind.fills": layers])))

        let nested = try #require(refusal.nested)
        #expect(nested.components == [.index(1), .key("colors"), .index(1), .key("position")])
        #expect(nested.indices == [1, 1])
        #expect(nested.keys == ["colors", "position"])
        #expect(nested.layerIndex == 1)
        #expect(nested.key == "position")
        #expect(refusal.property == "kind.fills")
        #expect(refusal.message.contains("kind.fills[1].colors[1].position"))
    }

    @Test("A fill written as one object has no layer index")
    func singleObjectHasNoIndex() throws {
        let image: AnyCodable = ["type": "image", "url": "a.png", "opacity": -0.1]
        let refusal = try #require(try refusal(.set(["kind.fills": image])))
        let nested = try #require(refusal.nested)

        #expect(nested.components == [.key("opacity")])
        #expect(nested.layerIndex == nil)
        #expect(nested.key == "opacity")
        #expect(nested.indices.isEmpty)
    }

    @Test("An off-step or out-of-range effect value carries its location too")
    func effectLocation() throws {
        let effects: AnyCodable = [["type": "shadow", "color": "#000000", "blur": 2], ["type": "blur", "radius": -4]]
        let refusal = try #require(try refusal(.set(["kind.effects": effects])))
        let nested = try #require(refusal.nested)

        #expect(nested.layerIndex == 1)
        #expect(nested.key == "radius")
    }

    @Test("A variable that does not exist, nested, carries its location")
    func undefinedVariableLocation() throws {
        let fill: AnyCodable = [["type": "color", "color": "#FF0000"], ["type": "color", "color": "$nope"]]
        let refusal = try #require(try refusal(.set(["kind.fills": fill])))

        #expect(refusal.code == .undefinedVariable)
        #expect(refusal.nested?.components == [.index(1), .key("color")])
    }

    @Test("A variable of the wrong type, nested, carries its location")
    func mismatchedVariableLocation() throws {
        let fill: AnyCodable = [["type": "color", "color": "$spacing"]]
        let refusal = try #require(try refusal(.set(["kind.fills": fill])))

        #expect(refusal.code == .variableTypeMismatch)
        #expect(refusal.nested?.layerIndex == 0)
        #expect(refusal.nested?.key == "color")
    }

    @Test("A refusal about the property itself has no nested location")
    func topLevelRefusalHasNone() throws {
        let refusal = try #require(try refusal(.set(["common.opacity": 7]), at: "Board/Row/Flow"))

        #expect(refusal.code == .outOfRange)
        #expect(refusal.nested == nil)
    }

    @Test("The location spells itself as the sentence does, under a property key")
    func spelling() {
        let location = EditRefusal.NestedLocation(components: [.index(0), .key("colors"), .index(1), .key("position")])
        #expect(location.spelled(under: "kind.fills") == "kind.fills[0].colors[1].position")
    }

    @Test("The location survives a JSON round trip")
    func codable() throws {
        let location = EditRefusal.NestedLocation(components: [.index(2), .key("radius")])
        let decoded = try JSONDecoder().decode(
            EditRefusal.NestedLocation.self, from: JSONEncoder().encode(location)
        )
        #expect(decoded == location)
    }
}
