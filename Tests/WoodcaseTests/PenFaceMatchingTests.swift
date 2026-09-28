//
//  PenFaceMatchingTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// A static family's weights resolve to the cut CSS font matching picks, as the browser
/// Pen runs in does — not the cut whose Core Text weight trait is nearest a fixed table's
/// guess, which drew IBM Plex Sans Medium as Regular and SemiBold as Medium (leaf BpaSrF,
/// `project/2026-09-28-pen-font-faces.md`, finding 1).
///
/// "Woodcase Static Sans" is Inter cut at 400, 500, 600 and 700
/// (`scripts/gen-static-test-family.py`), committed so the answer does not depend on the
/// fonts a machine has installed.
@Suite("Static face matching")
struct PenFaceMatchingTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    /// CSS Fonts 4 §5.2 step 4: an exact weight; between 400 and 500, heavier up to 500,
    /// then lighter, then heavier; below 400, lighter then heavier; above 500, heavier
    /// then lighter.
    @Test("The weight CSS picks among a family's cuts", arguments: [
        (450.0, [300.0, 400, 500, 600], 500.0),
        (450.0, [300.0, 400, 600], 400.0),
        (400.0, [300.0, 500, 600], 500.0),
        (500.0, [300.0, 400, 700], 400.0),
        (550.0, [400.0, 600, 700], 600.0),
        (600.0, [400.0, 700], 700.0),
        (600.0, [300.0, 400], 400.0),
        (300.0, [200.0, 400], 200.0),
        (300.0, [400.0, 700], 400.0),
        (275.0, [275.0, 400], 275.0),
    ])
    func cssWeightMatching(desired: Double, available: [Double], picked: Double) {
        #expect(PenFaceMatching.cssMatch(weight: desired, among: available) == picked)
    }

    @Test("A static family's weight draws the cut CSS picks", arguments: [
        ("450", "WoodcaseStaticSans-Medium"),
        ("500", "WoodcaseStaticSans-Medium"),
        ("medium", "WoodcaseStaticSans-Medium"),
        ("550", "WoodcaseStaticSans-SemiBold"),
        ("600", "WoodcaseStaticSans-SemiBold"),
        ("semibold", "WoodcaseStaticSans-SemiBold"),
        ("700", "WoodcaseStaticSans-Bold"),
        ("bold", "WoodcaseStaticSans-Bold"),
    ])
    func staticWeight(weight: String, postScriptName: String) {
        let font = PenTextMeasurer.resolveFont(family: "Woodcase Static Sans", size: 14, weight: weight, style: "normal")
        #expect(CTFontCopyPostScriptName(font) as String == postScriptName)
    }
}
