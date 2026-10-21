//
//  FigmaImportPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// P1 and I1: fills, gradients, blend modes, opacity and images.
struct FigmaImportPaintTests {
    private typealias Fixtures = FigmaImportFixtures

    /// The fills of the P1 node named `name`.
    private static func fills(_ name: String, caseID: String = "P1") throws -> [PenFill] {
        let node = try Fixtures.node(name, in: Fixtures.imported(caseID).clip.document)
        return node.kind.paintLists.fills?.all ?? []
    }

    /// The single gradient fill of the P1 node named `name`.
    private static func gradient(_ name: String) throws -> PenFill.PenGradientFill {
        let fills = try fills(name)
        guard fills.count == 1, case let .gradient(gradient) = fills[0] else {
            Issue.record("\(name): \(fills)")
            throw FigmaImportFixtures.FixtureMissing(name: name)
        }
        return gradient
    }

    @Test("A solid paint is a color fill, its paint opacity in the hex alpha")
    func solid() throws {
        #expect(try Self.fills("P1a solid") == [.color(PenFill.PenColorFill(color: .literal("#364FC7FF")))])
        let translucent = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "glass", id: 20, extra: [
            "fillPaints": .array([Fixtures.solid(1, 1, 1, 1, opacity: 0.3)]),
        ])
        let result = try FigmaImporter().clip(from: Fixtures.message([translucent]))
        let node = try #require(result.clip.document.children.first)
        #expect(node.kind.paintLists.fills?.all == [.color(PenFill.PenColorFill(color: .literal("#FFFFFF4D")))])
    }

    @Test("A linear gradient runs from Figma's start handle to its end handle")
    func linear() throws {
        let gradient = try Self.gradient("P1a linear")
        #expect(gradient.gradientType == .linear)
        #expect(gradient.colors == [
            PenFill.PenGradientStop(color: .literal("#364FC7FF"), position: .literal(0)),
            PenFill.PenGradientStop(color: .literal("#F08C00FF"), position: .literal(1)),
        ])
        let geometry = GradientGeometry(gradient)
        #expect(abs(geometry.linearStart.x - 0) < 1e-6 && abs(geometry.linearStart.y - 0.5) < 1e-6)
        #expect(abs(geometry.linearEnd.x - 1) < 1e-6 && abs(geometry.linearEnd.y - 0.5) < 1e-6)
    }

    @Test("A radial gradient fills the box's ellipse, and an angular one starts at the right")
    func radialAndAngular() throws {
        let radial = try Self.gradient("P1a radial")
        #expect(radial.gradientType == .radial)
        #expect(GradientGeometry(radial).isDefaultEllipse)
        let angular = try Self.gradient("P1a angular")
        #expect(angular.gradientType == .angular)
        // Pen's angular gradient starts pointing up; Figma's starts along its +x axis, so the
        // unrotated Figma gradient is Pen's turned a quarter clockwise: -90° counter-clockwise.
        let start = GradientGeometry(angular).point(NormalizedPoint(x: 0, y: -1))
        #expect(abs(start.x - 1.5) < 1e-6 && abs(start.y - 0.5) < 1e-6)
    }

    @Test("A rotated, scaled gradient transform keeps its handles")
    func transformedGradient() throws {
        // Figma maps the box into gradient space; this one runs down the middle at half length.
        let paint = KiwiValue.message(KiwiRecord(typeName: "Paint", fields: [
            "type": .enumeration("GRADIENT_LINEAR"), "visible": .bool(true), "opacity": .float(1),
            "stops": .array([0, 1].map { position in
                .structure(KiwiRecord(typeName: "ColorStop", fields: [
                    "color": .structure(KiwiRecord(typeName: "Color", fields: ["r": .float(1), "g": .float(0), "b": .float(0), "a": .float(1)])),
                    "position": .float(Float(position)),
                ]))
            }),
            "transform": .structure(KiwiRecord(typeName: "Matrix", fields: [
                "m00": .float(0), "m01": .float(2), "m02": .float(-0.5),
                "m10": .float(-1), "m11": .float(0), "m12": .float(1),
            ])),
        ]))
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "turned", id: 21, extra: ["fillPaints": .array([paint])])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        let fill = try #require(result.clip.document.children.first.flatMap { $0.kind.paintLists.fills?.all.first })
        guard case let .gradient(gradient) = fill else {
            Issue.record("\(fill)")
            return
        }
        // The inverse of the transform sends (0, 0.5) and (1, 0.5) to the handles.
        let geometry = GradientGeometry(gradient)
        #expect(abs(geometry.linearStart.x - 0.5) < 1e-6 && abs(geometry.linearStart.y - 0.25) < 1e-6)
        #expect(abs(geometry.linearEnd.x - 0.5) < 1e-6 && abs(geometry.linearEnd.y - 0.75) < 1e-6)
        #expect(result.losses.isEmpty)
    }

    @Test("A diamond gradient is drawn as a radial one, and reported")
    func diamond() throws {
        let gradient = try Self.gradient("P1a diamond")
        #expect(gradient.gradientType == .radial)
        let losses = try Fixtures.losses("P1a diamond", in: Fixtures.imported("P1"))
        #expect(losses.map(\.feature) == [.diamondGradient])
        #expect(losses.first?.treatment == .approximated)
    }

    @Test("Stacked fills keep their order, opacity and blend modes; the node's blend mode is kept")
    func stacked() throws {
        let fills = try Self.fills("P1b stacked fills")
        #expect(fills.count == 3)
        guard case let .gradient(middle) = fills[1], case let .color(top) = fills[2] else {
            Issue.record("\(fills)")
            return
        }
        #expect(middle.opacity == .literal(0.5))
        #expect(top.blendMode == .multiply)
        let node = try Fixtures.node("P1b stacked fills", in: Fixtures.imported("P1").clip.document)
        #expect(node.blendMode == .multiply)
    }

    @Test("Node opacity is the node's opacity")
    func opacity() throws {
        let node = try Fixtures.node("P1c half opacity", in: Fixtures.imported("P1").clip.document)
        #expect(node.common.opacity == .literal(0.5))
    }

    @Test("An image paint with no URL for its hash is dropped and reported with the hash")
    func imageWithoutBytes() throws {
        let result = try Fixtures.imported("I1")
        let node = try Fixtures.node("I1a image-fill", in: result.clip.document)
        #expect(node.kind.paintLists.fills == nil)
        let loss = try #require(Fixtures.losses("I1a image-fill", in: result).first)
        #expect(loss.feature == .imageNotEmbedded)
        #expect(loss.treatment == .dropped)
        #expect(loss.detail?.count == 40)
    }

    @Test("An image paint whose hash the caller resolved is an image fill, its scale mode and crop mapped")
    func imageWithURL() throws {
        let probe = try Fixtures.imported("I1")
        let hash = try #require(Fixtures.losses("I1a image-fill", in: probe).first?.detail)
        let result = try Fixtures.imported("I1", options: FigmaImportOptions(imageURLs: [hash: "./image.png"]))
        func image(_ name: String) throws -> PenFill.PenImageFill? {
            let node = try Fixtures.node(name, in: result.clip.document)
            guard case let .image(image)? = node.kind.paintLists.fills?.all.first else { return nil }
            return image
        }
        #expect(try image("I1a image-fill")?.mode == .cover)
        #expect(try image("I1a image-fill")?.url == "./image.png")
        #expect(try image("I1b image-fit")?.mode == .contain)
        let crop = try #require(try image("I1c image-crop"))
        #expect(crop.mode == .stretch)
        let transform = try #require(crop.transform)
        #expect(abs(transform.a - 2) < 1e-5 && abs(transform.d - 2) < 1e-5)
        #expect(abs(transform.tx + 0.8) < 1e-5 && abs(transform.ty + 0.2) < 1e-5)
        #expect(Fixtures.losses("I1a image-fill", in: result).isEmpty)
    }
}
