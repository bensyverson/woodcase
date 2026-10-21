//
//  FigmaImportStrokeEffectTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// P1's strokes and effects, and what the importer reports it could not carry.
struct FigmaImportStrokeEffectTests {
    private typealias Fixtures = FigmaImportFixtures

    private static func node(_ name: String) throws -> PenNode {
        try Fixtures.node(name, in: Fixtures.imported("P1").clip.document)
    }

    private static func losses(_ name: String) throws -> [FigmaImportLoss] {
        try Fixtures.losses(name, in: Fixtures.imported("P1"))
    }

    @Test("A stroke's alignment, width and paint map", arguments: [
        ("P1e stroke inside", PenStrokeAlign.inner),
        ("P1e stroke center", .center),
        ("P1e stroke outside", .outer),
    ])
    func alignment(name: String, align: PenStrokeAlign) throws {
        let node = try Self.node(name)
        let strokable = try #require(PenLayoutEngine.strokable(node))
        #expect(strokable.strokeAlignment == align)
        #expect(strokable.strokeWidth == .uniform(.literal(8)))
        #expect(strokable.stroke?.all == [.color(PenFill.PenColorFill(color: .literal("#364FC7FF")))])
        #expect(try Self.losses(name).isEmpty)
    }

    @Test("A node with no stroke paint has no stroke")
    func noStroke() throws {
        let strokable = try #require(PenLayoutEngine.strokable(Self.node("P1a solid")))
        #expect(strokable.stroke == nil && strokable.strokeWidth == nil)
    }

    @Test("Independent side weights are a per-side width; the dash Pen cannot draw with them is reported")
    func perSide() throws {
        let node = try Self.node("P1d per-side dashed")
        let strokable = try #require(PenLayoutEngine.strokable(node))
        #expect(strokable.strokeWidth == .perSide(PenStrokeWidth.Sides(
            top: .literal(1), right: .literal(2), bottom: .literal(4), left: .literal(8)
        )))
        #expect(try Self.losses("P1d per-side dashed").map(\.feature) == [.strokeDash])
    }

    @Test("A dash pattern on a uniform stroke is the node's dash")
    func dash() throws {
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "dashed", id: 30, extra: [
            "strokePaints": .array([Fixtures.solid(0, 0, 0)]), "strokeWeight": .float(2),
            "strokeAlign": .enumeration("CENTER"), "dashPattern": .array([.float(8), .float(4)]),
        ])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        let pen = try #require(result.clip.document.children.first)
        #expect(pen.strokeDash == PenStrokeDash(lengths: [8, 4], phase: 0))
        #expect(result.losses.isEmpty)
    }

    @Test("Butt, round and square caps and every join map; an arrow or marker cap is drawn butt and reported")
    func capsAndJoins() throws {
        #expect(try PenLayoutEngine.strokable(Self.node("P1d cap NONE"))?.strokeLinecap == .butt)
        #expect(try PenLayoutEngine.strokable(Self.node("P1d cap ROUND"))?.strokeLinecap == .round)
        #expect(try PenLayoutEngine.strokable(Self.node("P1d cap SQUARE"))?.strokeLinecap == .square)
        #expect(try PenLayoutEngine.strokable(Self.node("P1d join BEVEL"))?.strokeLinejoin == .bevel)
        #expect(try PenLayoutEngine.strokable(Self.node("P1d join ROUND"))?.strokeLinejoin == .round)
        #expect(try PenLayoutEngine.strokable(Self.node("P1d join MITER"))?.strokeLinejoin == .miter)
        for cap in ["ARROW_LINES", "ARROW_EQUILATERAL", "DIAMOND_FILLED", "TRIANGLE_FILLED", "CIRCLE_FILLED"] {
            let name = "P1d cap \(cap)"
            #expect(try PenLayoutEngine.strokable(Self.node(name))?.strokeLinecap == .butt, "\(name)")
            #expect(try Self.losses(name).map(\.feature) == [.strokeCap], "\(name)")
        }
    }

    @Test("A gradient stroke is a gradient stroke paint")
    func gradientStroke() throws {
        let strokable = try #require(PenLayoutEngine.strokable(Self.node("P1f gradient stroke")))
        guard case .gradient? = strokable.stroke?.all.first else {
            Issue.record("\(String(describing: strokable.stroke))")
            return
        }
    }

    @Test("Drop and inner shadows map their offset, blur and color")
    func shadows() throws {
        let drop = try Self.node("P1g drop shadow")
        #expect(PenRenderer.effects(for: drop)?.all == [.shadow(PenEffect.PenShadowEffect(
            shadowType: .outer, offset: PenEffect.PenOffset(x: .literal(4), y: .literal(4)),
            blur: .literal(8), color: .literal("#00000040")
        ))])
        let inner = try Self.node("P1g inner shadow")
        #expect(PenRenderer.effects(for: inner)?.all == [.shadow(PenEffect.PenShadowEffect(
            shadowType: .inner, offset: PenEffect.PenOffset(x: .literal(2), y: .literal(2)),
            blur: .literal(4), color: .literal("#00000040")
        ))])
        #expect(try Self.losses("P1g drop shadow").isEmpty)
    }

    @Test("A shadow's spread is the node's shadow spread")
    func spread() throws {
        let effect = KiwiValue.message(KiwiRecord(typeName: "Effect", fields: [
            "type": .enumeration("DROP_SHADOW"), "visible": .bool(true), "radius": .float(4), "spread": .float(3),
            "offset": .structure(KiwiRecord(typeName: "Vector", fields: ["x": .float(0), "y": .float(2)])),
            "color": .structure(KiwiRecord(typeName: "Color", fields: ["r": .float(0), "g": .float(0), "b": .float(0), "a": .float(1)])),
            "blendMode": .enumeration("NORMAL"), "showShadowBehindNode": .bool(false),
        ]))
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "spread", id: 31, extra: [
            "fillPaints": .array([Fixtures.solid(1, 1, 1)]), "effects": .array([effect]),
        ])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        let pen = try #require(result.clip.document.children.first)
        #expect(pen.shadowSpread(forEffect: 0) == 3)
        #expect(result.losses.isEmpty)
    }

    @Test("Layer and background blurs map their radius")
    func blurs() throws {
        #expect(try PenRenderer.effects(for: Self.node("P1g layer blur"))?.all == [
            .blur(PenEffect.PenBlurEffect(radius: .literal(4))),
        ])
        #expect(try PenRenderer.effects(for: Self.node("P1g background blur"))?.all == [
            .backgroundBlur(PenEffect.PenBackgroundBlurEffect(radius: .literal(8))),
        ])
    }

    @Test("A progressive blur, noise, texture and glass are dropped and reported", arguments: [
        ("P1g progressive blur", FigmaImportLoss.Feature.progressiveBlur),
        ("P1g noise", .unsupportedEffect),
        ("P1g texture", .unsupportedEffect),
        ("P1g glass", .unsupportedEffect),
    ])
    func unsupportedEffects(name: String, feature: FigmaImportLoss.Feature) throws {
        #expect(try PenRenderer.effects(for: Self.node(name)) == nil)
        let losses = try Self.losses(name)
        #expect(losses.map(\.feature) == [feature])
        #expect(losses.first?.treatment == .dropped)
    }

    @Test("A drop shadow Figma shows behind a translucent fill is reported: Pen knocks it out")
    func shadowBehindTranslucentFill() throws {
        let effect = KiwiValue.message(KiwiRecord(typeName: "Effect", fields: [
            "type": .enumeration("DROP_SHADOW"), "visible": .bool(true), "radius": .float(4),
            "offset": .structure(KiwiRecord(typeName: "Vector", fields: ["x": .float(0), "y": .float(2)])),
            "color": .structure(KiwiRecord(typeName: "Color", fields: ["r": .float(0), "g": .float(0), "b": .float(0), "a": .float(1)])),
            "blendMode": .enumeration("NORMAL"), "showShadowBehindNode": .bool(true),
        ]))
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "veil", id: 32, extra: [
            "fillPaints": .array([Fixtures.solid(1, 1, 1, 0.5)]), "effects": .array([effect]),
        ])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        #expect(result.losses.map(\.feature) == [.shadowBehindNode])
    }
}
