//
//  StateDefinitionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct StateDefinitionTests {
    // MARK: - StateTrigger

    @Test("A trigger names the state, not a selector")
    func stateTrigger() {
        let trigger = StateTrigger.hover
        #expect(trigger == .hover)
        #expect(trigger != .pressed)
    }

    @Test("An attribute trigger carries its name and value")
    func attributeTrigger() {
        let trigger = StateTrigger.attribute(name: "enabled", value: "true")
        #expect(trigger == .attribute(name: "enabled", value: "true"))
        #expect(trigger != .attribute(name: "enabled", value: "false"))
    }

    // MARK: - StateSource

    @Test("StateSource raw values")
    func sourceRawValues() {
        #expect(StateSource(rawValue: "smartDefault") == .smartDefault)
        #expect(StateSource(rawValue: "designerOverride") == .designerOverride)
        #expect(StateSource(rawValue: "binding") == .binding)
    }

    // MARK: - StateDefinition Codable

    @Test("StateDefinition round-trips through JSON")
    func codableRoundTrip() throws {
        let definition = StateDefinition(
            name: "hover",
            trigger: .hover,
            source: .smartDefault,
            isStructural: false,
            deltas: [
                StateDelta(
                    nodePath: ".",
                    changes: [PropertyChange(property: .opacity, value: .double(0.95))]
                ),
            ],
            variantNode: nil
        )

        let data = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(StateDefinition.self, from: data)

        #expect(decoded.name == definition.name)
        #expect(decoded.trigger == definition.trigger)
        #expect(decoded.source == definition.source)
        #expect(decoded.isStructural == definition.isStructural)
        #expect(decoded.deltas == definition.deltas)
    }

    // MARK: - Equatable

    @Test("StateDefinitions with same values are equal")
    func equatable() {
        let a = StateDefinition(
            name: "hover",
            trigger: .hover,
            source: .smartDefault,
            isStructural: false,
            deltas: [],
            variantNode: nil
        )
        let b = StateDefinition(
            name: "hover",
            trigger: .hover,
            source: .smartDefault,
            isStructural: false,
            deltas: [],
            variantNode: nil
        )
        #expect(a == b)
    }

    @Test("StateDefinitions with different names are not equal")
    func notEqual() {
        let a = StateDefinition(
            name: "hover",
            trigger: .hover,
            source: .smartDefault,
            isStructural: false,
            deltas: [],
            variantNode: nil
        )
        let b = StateDefinition(
            name: "pressed",
            trigger: .pressed,
            source: .smartDefault,
            isStructural: false,
            deltas: [],
            variantNode: nil
        )
        #expect(a != b)
    }

    // MARK: - DeltaProperty

    @Test("DeltaProperty raw values cover expected properties")
    func deltaPropertyCoverage() {
        let allCases: [DeltaProperty] = [
            .fills, .strokeColor, .strokeWidth, .cornerRadius,
            .opacity, .width, .height, .padding, .gap,
            .textColor, .fontSize, .fontWeight, .shadow, .blur, .transform,
        ]
        #expect(allCases.count == 15)
    }
}
