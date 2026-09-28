//
//  PenHexColorTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Testing
@testable import Woodcase

struct PenHexColorTests {
    /// Every form the grammar accepts, with the channels it spells.
    private static let accepted: [(String, PenHexColor)] = [
        ("#FF8000", PenHexColor(red: 255, green: 128, blue: 0)),
        ("ff8000", PenHexColor(red: 255, green: 128, blue: 0)),
        ("#0000FF80", PenHexColor(red: 0, green: 0, blue: 255, alpha: 128)),
        ("#F0a", PenHexColor(red: 255, green: 0, blue: 170)),
        ("F0A", PenHexColor(red: 255, green: 0, blue: 170)),
        ("#00000000", PenHexColor(red: 0, green: 0, blue: 0, alpha: 0)),
    ]

    /// Strings the grammar refuses: wrong lengths (including four-digit `#RGBA`),
    /// non-hex digits, a doubled `#`, surrounding space and a sign `UInt64` would take.
    private static let refused = [
        "", "#", "#12", "#1234", "#F008", "#12345", "#1234567", "#123456789",
        "#GGGGGG", "##FFF", " #FFF", "#FFF ", "#+12345", "#-12345", "+FFFFFF", "#+1234567",
        "#１２３", // fullwidth digits
    ]

    @Test("Accepted forms parse to their channels", arguments: accepted)
    func parses(hex: String, expected: PenHexColor) {
        #expect(PenHexColor(hex) == expected)
    }

    @Test("Refused forms parse to nil", arguments: refused)
    func refuses(hex: String) {
        #expect(PenHexColor(hex) == nil)
    }

    @Test("Unit components are each channel over 255, alpha last")
    func unitComponents() {
        let color = PenHexColor(red: 255, green: 0, blue: 51, alpha: 102)
        #expect(color.unitComponents == [1, 0, 0.2, 0.4])
    }

    /// Pen's mesh reads a malformed colour its own way (``PenMeshColor/hexColor(penMesh:)``),
    /// but every form the grammar accepts means the same colour to both.
    @Test("PenColorParser and PenMeshColor agree on every accepted form", arguments: accepted.map(\.0))
    func entryPointsAgree(hex: String) throws {
        let cg = try #require(PenColorParser.parse(hex)?.components)
        let mesh = PenMeshColor(penMesh: hex)
        #expect(cg.map(Double.init) == [mesh.red, mesh.green, mesh.blue, mesh.alpha], "\(hex)")
    }
}
