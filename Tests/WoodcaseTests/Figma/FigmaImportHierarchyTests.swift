//
//  FigmaImportHierarchyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the importer builds the tree: roots, order, node kinds and the frame settings that
/// keep Figma's absolute positions.
struct FigmaImportHierarchyTests {
    private typealias Fixtures = FigmaImportFixtures

    @Test("The roots are the page's children, in layer order, and they are the clip's content")
    func roots() throws {
        let result = try Fixtures.imported("M1a")
        #expect(result.clip.document.children.map(\.common.name) == ["M1a child one", "M1a child two"])
        #expect(result.clip.contentIDs == result.clip.document.children.map(\.id))
        #expect(result.clip.origins == nil)
        #expect(result.clip.sourceDocumentID == nil)
    }

    @Test("A node's id is derived from its Figma GUID")
    func ids() throws {
        let result = try Fixtures.imported("M1a")
        #expect(result.clip.document.children.map(\.id) == ["figma-1-483", "figma-1-485"])
        #expect(FigmaImporter.penID(sessionID: 1, localID: 483) == "figma-1-483")
    }

    @Test("Children follow their parentIndex position, bottom layer first")
    func childOrder() throws {
        let result = try Fixtures.imported("G1")
        let frame = try Fixtures.node("G1g constraints", in: result.clip.document)
        #expect(Fixtures.children(of: frame).map(\.common.name) == [
            "G1g left top", "G1g right top", "G1g center", "G1g left and right", "G1g scale",
        ])
    }

    @Test("A frame Figma resizes to fit its children is a group")
    func groups() throws {
        let result = try Fixtures.imported("G1")
        for name in ["G1b flip horizontal", "G1c outer group", "G1c inner group", "G1e mask"] {
            let node = try Fixtures.node(name, in: result.clip.document)
            guard case .group = node.kind else {
                Issue.record("\(name) is \(node.kind)")
                continue
            }
        }
    }

    @Test("A frame lays out nothing, so its children keep Figma's positions, and clips unless Figma said not to")
    func frames() throws {
        let result = try Fixtures.imported("G1")
        let node = try Fixtures.node("G1d clipped", in: result.clip.document)
        guard case let .frame(data) = node.kind else {
            Issue.record("not a frame")
            return
        }
        #expect(data.layout == PenLayoutDirection.none)
        #expect(data.clip == .literal(true))
    }

    @Test("A turned frame and a flipped group decompose into Pen's rotation and flips")
    func transforms() throws {
        let result = try Fixtures.imported("G1")
        let rotated = try Fixtures.node("G1a rotated", in: result.clip.document)
        #expect(abs((rotated.common.rotation?.literalValue ?? 0) - 15) < 0.001)
        #expect(rotated.common.x == .literal(60) && rotated.common.y == .literal(40))
        let flipped = try Fixtures.node("G1b flip horizontal", in: result.clip.document)
        #expect(flipped.common.flipX == .literal(true))
        #expect(flipped.common.rotation == nil)
        let vertical = try Fixtures.node("G1b flip vertical", in: result.clip.document)
        #expect(vertical.common.flipY == .literal(true))
        #expect(vertical.common.flipX == nil && vertical.common.rotation == nil)
    }

    @Test("A section is a frame, reported as one")
    func section() throws {
        let result = try Fixtures.imported("G1")
        let node = try Fixtures.node("G1f section", in: result.clip.document)
        guard case .frame = node.kind else {
            Issue.record("not a frame")
            return
        }
        #expect(Fixtures.losses("G1f section", in: result).map(\.feature) == [.section])
    }

    @Test("A mask is reported, and the mask shape no longer draws")
    func mask() throws {
        let result = try Fixtures.imported("G1")
        let node = try Fixtures.node("G1e mask shape", in: result.clip.document)
        #expect(node.common.enabled == .literal(false))
        #expect(Fixtures.losses("G1e mask shape", in: result).map(\.feature) == [.mask])
    }

    @Test("A constraint other than left and top is reported")
    func constraints() throws {
        let result = try Fixtures.imported("G1")
        #expect(Fixtures.losses("G1g left top", in: result).isEmpty)
        for name in ["G1g right top", "G1g center", "G1g left and right", "G1g scale"] {
            #expect(Fixtures.losses(name, in: result).map(\.feature) == [.constraints], "\(name)")
        }
    }

    @Test("An auto layout frame keeps its children where Figma placed them, and is reported")
    func autoLayout() throws {
        let result = try Fixtures.imported("L1")
        let row = try Fixtures.node("L1a row", in: result.clip.document)
        guard case let .frame(data) = row.kind else {
            Issue.record("not a frame")
            return
        }
        #expect(data.layout == PenLayoutDirection.none)
        let item = try Fixtures.node("L1a item 2", in: result.clip.document)
        #expect(item.common.x == .literal(140) && item.common.y == .literal(16))
        #expect(Fixtures.losses("L1a row", in: result).map(\.feature) == [.autoLayout])
        #expect(Fixtures.losses("L1f grids", in: result).map(\.feature) == [.layoutGrid])
    }

    @Test("A hidden node is disabled and a translucent one keeps its opacity")
    func visibilityAndOpacity() throws {
        let hidden = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "hidden", id: 10, extra: ["visible": .bool(false), "opacity": .float(0.5)])
        let result = try FigmaImporter().clip(from: Fixtures.message([hidden]))
        let node = try #require(result.clip.document.children.first)
        #expect(node.common.enabled == .literal(false))
        #expect(node.common.opacity == .literal(0.5))
    }

    @Test("Every committed case imports, and a field the importer does not read is reported, never dropped silently",
          arguments: KiwiFixtures.caseIDs)
    func everyCaseImports(caseID: String) throws {
        let result = try Fixtures.imported(caseID)
        #expect(!result.clip.document.children.isEmpty)
        #expect(!result.losses.contains { $0.feature == .unreadField }, "\(result.losses.filter { $0.feature == .unreadField })")
    }

    @Test("A field the importer has never met is reported by name")
    func unreadField() throws {
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "odd", id: 11, extra: ["futureField": .bool(true)])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        let loss = try #require(result.losses.first)
        #expect(loss.feature == .unreadField)
        #expect(loss.detail == "futureField")
        #expect(loss.nodeID == "figma-1-11")
    }

    @Test("A locked layer stays locked")
    func locked() throws {
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "pinned", id: 12, extra: ["locked": .bool(true)])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        let pen = try #require(result.clip.document.children.first)
        #expect(pen.isLocked)
        #expect(result.losses.isEmpty)
        let open = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "open", id: 13, extra: ["locked": .bool(false)])
        let unlocked = try #require(FigmaImporter().clip(from: Fixtures.message([open])).clip.document.children.first)
        #expect(!unlocked.isLocked)
        #expect(unlocked.common.metadata == nil)
    }

    @Test("A field harmless at its default is reported when it is not at its default", arguments: [
        ("textTracking", KiwiValue.float(0.5)),
        ("fontVariations", .array([.message(KiwiRecord(typeName: "FontVariation", fields: ["axisTag": .uint(1)]))])),
        ("fontVariantCommonLigatures", .bool(false)),
        ("textDecorationSkipInk", .bool(false)),
    ])
    func nonDefault(field: String, value: KiwiValue) throws {
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "odd", id: 14, extra: [field: value])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        #expect(result.losses.map(\.feature) == [.unreadField])
        #expect(result.losses.first?.detail == field)
    }

    @Test("A page's own fields are reported when a mapped node carries them", arguments: ["backgroundEnabled", "internalOnly"])
    func pageFields(field: String) throws {
        let node = Fixtures.nodeChange("ROUNDED_RECTANGLE", name: "odd", id: 15, extra: [field: .bool(true)])
        let result = try FigmaImporter().clip(from: Fixtures.message([node]))
        #expect(result.losses.map(\.detail) == [field])
    }
}
