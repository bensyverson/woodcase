//
//  PenMeshFillRendererTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins how ``PenFillRenderer`` composites a mesh gradient: over the domain, through the
/// clip, with the fill's own opacity and blend mode, and not at all when Pen would not.
struct PenMeshFillRendererTests {
    private typealias RGBA = PenFillDomainTests.RGBA

    @Test("The mesh is laid out over the domain, not the clip")
    func domainPlacesTheMesh() throws {
        // Top row red → green, bottom row blue → yellow, over a 200 × 40 domain.
        let image = try render(
            Self.mesh(["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]),
            clip: CGRect(x: 150, y: 0, width: 50, height: 40),
            domain: CGRect(x: 0, y: 0, width: 200, height: 40)
        )
        // Left of the clip: nothing.
        #expect(image.pixel(10, 0).a == 0)
        // The clip's top-right pixel is the domain's top-right corner: green, not a
        // colour from the middle of the ramp.
        let corner = image.pixel(199, 0)
        #expect(corner.g >= 254 && corner.r <= 1 && corner.a == 255, "corner \(corner)")
        // Its left edge sits three quarters of the way along: smoothstep(0.75) ≈ 0.84 green.
        let edge = image.pixel(150, 0)
        #expect(edge.g > 200 && edge.r > 20, "edge \(edge)")
    }

    @Test("A domain offset from the origin moves the mesh with it")
    func offsetDomain() throws {
        let image = try render(
            Self.mesh(["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]),
            clip: CGRect(x: 0, y: 0, width: 200, height: 40),
            domain: CGRect(x: 50, y: 10, width: 100, height: 20)
        )
        // The mesh covers only its domain, even where the clip reaches further.
        #expect(image.pixel(49, 15).a == 0)
        #expect(image.pixel(100, 5).a == 0)
        let topLeft = image.pixel(50, 10)
        #expect(topLeft.r >= 254 && topLeft.g <= 1 && topLeft.a == 255, "top-left \(topLeft)")
        let bottomRight = image.pixel(149, 29)
        #expect(bottomRight.r >= 254 && bottomRight.g >= 254 && bottomRight.b <= 1, "bottom-right \(bottomRight)")
    }

    @Test("The fill's opacity scales its coverage")
    func opacity() throws {
        let image = try render(Self.mesh(Array(repeating: "#FF0000", count: 4), opacity: 0.5))
        let pixel = image.pixel(20, 20)
        #expect(abs(Int(pixel.a) - 128) <= 1 && abs(Int(pixel.r) - 128) <= 1, "pixel \(pixel)")
    }

    @Test("The fill's blend mode composites it onto what is under it")
    func blendMode() throws {
        let image = try render(
            Self.mesh(Array(repeating: "#FF0000", count: 4), blendMode: .multiply),
            background: CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        )
        // Multiply: red × grey is dark red, where normal would be pure red.
        let pixel = image.pixel(20, 20)
        #expect(abs(Int(pixel.r) - 128) <= 1 && pixel.g == 0 && pixel.a == 255, "pixel \(pixel)")
    }

    @Test("A disabled mesh draws nothing")
    func disabled() throws {
        let colors = Array(repeating: "#FF0000", count: 4)
        #expect(try render(Self.mesh(colors)).pixel(20, 20).a == 255)
        #expect(try render(Self.mesh(colors, enabled: false)).pixel(20, 20).a == 0)
    }

    @Test("A mesh Pen would drop draws nothing: a count that is not columns × rows")
    func invalidMesh() throws {
        let colors = Array(repeating: "#FF0000", count: 4)
        #expect(try render(Self.mesh(colors)).pixel(20, 20).a == 255)
        #expect(try render(Self.mesh(Array(colors.dropLast()))).pixel(20, 20).a == 0)
    }

    // MARK: - Helpers

    /// A 2×2 mesh with default points and the given row-major colours.
    private static func mesh(
        _ colors: [String],
        opacity: Double? = nil,
        blendMode: PenBlendMode? = nil,
        enabled: Bool? = nil
    ) -> PenFill {
        .meshGradient(PenFill.PenMeshGradientFill(
            enabled: enabled.map(PenValue.literal),
            blendMode: blendMode,
            opacity: opacity.map(PenValue.literal),
            columns: 2,
            rows: 2,
            colors: colors.map(PenValue.literal),
            points: [.bare(.init(0, 0)), .bare(.init(1, 0)), .bare(.init(0, 1)), .bare(.init(1, 1))]
        ))
    }

    /// Draws one fill into a 200 × 40 y-down bitmap at 1x and reads it back.
    private func render(
        _ fill: PenFill,
        clip: CGRect = CGRect(x: 0, y: 0, width: 200, height: 40),
        domain: CGRect = CGRect(x: 0, y: 0, width: 200, height: 40),
        background: CGColor? = nil
    ) throws -> RGBA {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 40,
            bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.translateBy(x: 0, y: 40)
        context.scaleBy(x: 1, y: -1)
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 40))
        }
        PenFillRenderer.renderFills(
            .single(fill),
            clip: CGPath(rect: clip, transform: nil),
            fillRule: .winding,
            domain: domain,
            in: context
        )
        let image = try #require(context.makeImage())
        return try #require(RGBA(image))
    }
}
