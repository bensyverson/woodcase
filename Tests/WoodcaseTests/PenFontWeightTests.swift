//
//  PenFontWeightTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

/// The one reading of a .pen `fontWeight` string as a CSS weight, shared by the Core Text
/// renderer and the SwiftUI emitter.
struct PenFontWeightTests {
    @Test("Keywords map to their CSS weights", arguments: [
        ("thin", 100.0), ("extralight", 200), ("ultralight", 200), ("light", 300),
        ("normal", 400), ("regular", 400), ("medium", 500), ("semibold", 600),
        ("demibold", 600), ("bold", 700), ("extrabold", 800), ("ultrabold", 800),
        ("black", 900), ("heavy", 900), ("Bold", 700),
    ])
    func keywords(keyword: String, weight: Double) {
        #expect(PenFontWeight.cssWeight(keyword) == weight)
    }

    @Test("A number is its own weight, and anything else is 400")
    func numbersAndUnknowns() {
        #expect(PenFontWeight.cssWeight("650") == 650)
        #expect(PenFontWeight.cssWeight("chunky") == 400)
    }

    @Test("The Core Text renderer reads weights the same way")
    func measurerAgrees() {
        for keyword in ["thin", "bold", "650", "chunky"] {
            #expect(PenTextMeasurer.mapWeightToAxisValue(keyword) == PenFontWeight.cssWeight(keyword))
        }
    }
}
