//
//  PenTextMeasurerVariableFontTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("PenTextMeasurer Variable Font Support")
struct PenTextMeasurerVariableFontTests {
    // MARK: - mapWeightToAxisValue

    @Test("Maps numeric weight strings to axis values")
    func mapsNumericWeights() {
        #expect(PenTextMeasurer.mapWeightToAxisValue("100") == 100)
        #expect(PenTextMeasurer.mapWeightToAxisValue("400") == 400)
        #expect(PenTextMeasurer.mapWeightToAxisValue("700") == 700)
        #expect(PenTextMeasurer.mapWeightToAxisValue("900") == 900)
    }

    @Test("Maps named weight strings to axis values")
    func mapsNamedWeights() {
        #expect(PenTextMeasurer.mapWeightToAxisValue("thin") == 100)
        #expect(PenTextMeasurer.mapWeightToAxisValue("extralight") == 200)
        #expect(PenTextMeasurer.mapWeightToAxisValue("ultralight") == 200)
        #expect(PenTextMeasurer.mapWeightToAxisValue("light") == 300)
        #expect(PenTextMeasurer.mapWeightToAxisValue("normal") == 400)
        #expect(PenTextMeasurer.mapWeightToAxisValue("regular") == 400)
        #expect(PenTextMeasurer.mapWeightToAxisValue("medium") == 500)
        #expect(PenTextMeasurer.mapWeightToAxisValue("semibold") == 600)
        #expect(PenTextMeasurer.mapWeightToAxisValue("demibold") == 600)
        #expect(PenTextMeasurer.mapWeightToAxisValue("bold") == 700)
        #expect(PenTextMeasurer.mapWeightToAxisValue("extrabold") == 800)
        #expect(PenTextMeasurer.mapWeightToAxisValue("ultrabold") == 800)
        #expect(PenTextMeasurer.mapWeightToAxisValue("black") == 900)
        #expect(PenTextMeasurer.mapWeightToAxisValue("heavy") == 900)
    }

    @Test("Maps unknown weight string to 400")
    func mapsUnknownWeightToDefault() {
        #expect(PenTextMeasurer.mapWeightToAxisValue("unknown") == 400)
    }

    @Test("Is case-insensitive")
    func caseInsensitive() {
        #expect(PenTextMeasurer.mapWeightToAxisValue("Bold") == 700)
        #expect(PenTextMeasurer.mapWeightToAxisValue("THIN") == 100)
    }
}
