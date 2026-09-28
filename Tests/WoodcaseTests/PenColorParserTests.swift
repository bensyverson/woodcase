//
//  PenColorParserTests.swift
//  Woodcase
//

import CoreGraphics
import Testing
@testable import Woodcase

struct PenColorParserTests {
    // MARK: - Valid 6-char hex

    @Test("#FF0000 parses to red")
    func sixCharRed() throws {
        let color = try #require(PenColorParser.parse("#FF0000"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0) // red
        #expect(components[1] == 0.0) // green
        #expect(components[2] == 0.0) // blue
        #expect(components[3] == 1.0) // alpha
    }

    @Test("#00FF00 parses to green")
    func sixCharGreen() throws {
        let color = try #require(PenColorParser.parse("#00FF00"))
        let components = try #require(color.components)
        #expect(components[0] == 0.0)
        #expect(components[1] == 1.0)
        #expect(components[2] == 0.0)
        #expect(components[3] == 1.0)
    }

    @Test("#0000FF parses to blue")
    func sixCharBlue() throws {
        let color = try #require(PenColorParser.parse("#0000FF"))
        let components = try #require(color.components)
        #expect(components[0] == 0.0)
        #expect(components[1] == 0.0)
        #expect(components[2] == 1.0)
        #expect(components[3] == 1.0)
    }

    @Test("#000000 parses to black")
    func sixCharBlack() throws {
        let color = try #require(PenColorParser.parse("#000000"))
        let components = try #require(color.components)
        #expect(components[0] == 0.0)
        #expect(components[1] == 0.0)
        #expect(components[2] == 0.0)
        #expect(components[3] == 1.0)
    }

    @Test("#FFFFFF parses to white")
    func sixCharWhite() throws {
        let color = try #require(PenColorParser.parse("#FFFFFF"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        #expect(components[1] == 1.0)
        #expect(components[2] == 1.0)
        #expect(components[3] == 1.0)
    }

    // MARK: - 8-char hex (with alpha)

    @Test("#FF000080 parses to red at ~50% alpha")
    func eightCharWithAlpha() throws {
        let color = try #require(PenColorParser.parse("#FF000080"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        #expect(components[1] == 0.0)
        #expect(components[2] == 0.0)
        let expectedAlpha = Double(0x80) / 255.0
        #expect(abs(components[3] - expectedAlpha) < 0.001)
    }

    @Test("#FFFFFF00 parses to fully transparent white")
    func eightCharFullyTransparent() throws {
        let color = try #require(PenColorParser.parse("#FFFFFF00"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        #expect(components[1] == 1.0)
        #expect(components[2] == 1.0)
        #expect(components[3] == 0.0)
    }

    // MARK: - 3-char shorthand

    @Test("#F00 shorthand parses to red")
    func threeCharRed() throws {
        let color = try #require(PenColorParser.parse("#F00"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        #expect(components[1] == 0.0)
        #expect(components[2] == 0.0)
        #expect(components[3] == 1.0)
    }

    @Test("#ABC shorthand expands correctly")
    func threeCharExpansion() throws {
        let color = try #require(PenColorParser.parse("#ABC"))
        let components = try #require(color.components)
        let expectedR = Double(0xAA) / 255.0
        let expectedG = Double(0xBB) / 255.0
        let expectedB = Double(0xCC) / 255.0
        #expect(abs(components[0] - expectedR) < 0.001)
        #expect(abs(components[1] - expectedG) < 0.001)
        #expect(abs(components[2] - expectedB) < 0.001)
        #expect(components[3] == 1.0)
    }

    // MARK: - Without # prefix

    @Test("FF0000 without # prefix still parses")
    func withoutHashPrefix() throws {
        let color = try #require(PenColorParser.parse("FF0000"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        #expect(components[1] == 0.0)
        #expect(components[2] == 0.0)
        #expect(components[3] == 1.0)
    }

    // MARK: - Invalid input

    @Test("Invalid hex characters return nil")
    func invalidHexChars() {
        #expect(PenColorParser.parse("#GGHHII") == nil)
    }

    @Test("Too short string returns nil")
    func tooShort() {
        #expect(PenColorParser.parse("#FF") == nil)
    }

    @Test("Empty string returns nil")
    func emptyString() {
        #expect(PenColorParser.parse("") == nil)
    }

    @Test("Wrong length (4 chars) returns nil")
    func wrongLength() {
        #expect(PenColorParser.parse("#FFFF") == nil)
    }

    // MARK: - Extended linear sRGB color space

    @Test("Parses into extended linear sRGB when color space provided")
    func extendedLinearSRGB() throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let color = try #require(PenColorParser.parse("#FF0000", colorSpace: colorSpace))
        #expect(color.colorSpace?.name == CGColorSpace.extendedLinearSRGB)
    }

    // MARK: - Lowercase hex

    @Test("Lowercase hex parses correctly")
    func lowercaseHex() throws {
        let color = try #require(PenColorParser.parse("#ff8800"))
        let components = try #require(color.components)
        #expect(components[0] == 1.0)
        let expectedG = Double(0x88) / 255.0
        #expect(abs(components[1] - expectedG) < 0.001)
        #expect(components[2] == 0.0)
        #expect(components[3] == 1.0)
    }
}
