//
//  PenIconFontParserTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenIconFontParserTests {
    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> PenDocument {
        let nameWithoutExtension = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: nameWithoutExtension, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureError.notFound(name)
        }
        return try PenParser.parse(contentsOf: url)
    }

    enum FixtureError: Error {
        case notFound(String)
    }

    private func iconChildren() throws -> [PenNode] {
        let doc = try loadFixture("parser-icon-font.pen")
        guard case let .frame(frameData) = doc.children[0].kind,
              let children = frameData.children
        else {
            Issue.record("Expected frame with children")
            return []
        }
        return children
    }

    // MARK: - Parsing

    @Test("Parses icon nodes for all 6 font families")
    func parseAllFamilies() throws {
        let children = try iconChildren()
        #expect(children.count == 10)

        let expectedFamilies = [
            "Material Symbols Outlined",
            "Material Symbols Rounded",
            "Material Symbols Sharp",
            "feather",
            "phosphor",
            "feather",
            "lucide",
            "phosphor",
            "lucide",
            "phosphor",
        ]

        for (i, child) in children.enumerated() {
            guard case let .icon(data) = child.kind else {
                Issue.record("Expected icon kind at index \(i)")
                continue
            }
            #expect(data.library == .literal(expectedFamilies[i]))
        }
    }

    @Test("Parses icon width and height")
    func parseIconSizing() throws {
        let children = try iconChildren()

        // icon1: Material Symbols Outlined 48x48
        guard case let .icon(data1) = children[0].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data1.width == .fixed(48))
        #expect(data1.height == .fixed(48))

        // feather bell: 24x24
        guard case let .icon(data4) = children[3].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data4.width == .fixed(24))
        #expect(data4.height == .fixed(24))

        // feather loader: non-square 12x24
        guard case let .icon(data6) = children[5].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data6.width == .fixed(12))
        #expect(data6.height == .fixed(24))
    }

    @Test("Parses icon with weight")
    func parseIconWeight() throws {
        let children = try iconChildren()

        // icon2 (lucide ellipsis): weight 400
        guard case let .icon(data) = children[8].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data.icon == .literal("ellipsis"))
        #expect(data.weight == .literal(400))
    }

    @Test("Parses icon fill colors")
    func parseIconFills() throws {
        let children = try iconChildren()

        // icon1: solid black
        guard case let .icon(data1) = children[0].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data1.fills != nil)

        // feather bell: red
        guard case let .icon(data4) = children[3].kind else {
            Issue.record("Expected icon kind"); return
        }
        #expect(data4.fills != nil)
    }

    // MARK: - Round-trip

    @Test("IconData round-trips through encode/decode")
    func iconRoundTrip() throws {
        let doc = try loadFixture("parser-icon-font.pen")
        let encoded = try PenParser.encodeToString(doc)
        let decoded = try PenParser.parse(encoded)

        guard case let .frame(frameData) = decoded.children[0].kind,
              let children = frameData.children
        else {
            Issue.record("Expected frame with children after round-trip")
            return
        }

        #expect(children.count == 10)

        guard case let .icon(data) = children[0].kind else {
            Issue.record("Expected icon after round-trip")
            return
        }
        #expect(data.icon == .literal("vpn_lock"))
        #expect(data.library == .literal("Material Symbols Outlined"))
        #expect(data.width == .fixed(48))
        #expect(data.height == .fixed(48))
    }
}
