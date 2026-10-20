//
//  FigmaGeometryOracleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Decoded blob geometry against Figma's own SVG export of the same fixture: vector
/// networks (V1, P1) and glyph outlines (T1), within 0.01 pt.
struct FigmaGeometryOracleTests {
    private typealias Blobs = FigmaBlobTableTests

    /// The translation of a node's `transform`: where its local origin sits in the
    /// selection root, which is the SVG's coordinate space.
    private static func offset(_ node: KiwiValue) throws -> FigmaPoint {
        let transform = try #require(node["transform"])
        #expect(transform["m00"]?.floatValue == 1 && transform["m11"]?.floatValue == 1, "unrotated")
        return try FigmaPoint(
            x: Double(#require(transform["m02"]?.floatValue)),
            y: Double(#require(transform["m12"]?.floatValue))
        )
    }

    /// The node's vector network, its region paths joined, in the selection root's space.
    private static func fillPath(_ name: String, in caseID: String) throws -> (FigmaPath, FigmaVectorNetwork) {
        let node = try Blobs.node(name, in: caseID)
        let index = try #require(node["vectorData"]?["vectorNetworkBlob"]?.uintValue, "\(name) has a network")
        let network = try FigmaBlobTable(message: Blobs.message(caseID)).vectorNetwork(at: index)
        let offset = try offset(node)
        let commands = try network.regions.indices.flatMap { try network.path(ofRegion: $0).commands }
        let path = FigmaPath(commands: commands).mapped { FigmaPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        return (path, network)
    }

    /// The reference element that draws `path`, if any.
    private static func element(matching path: FigmaPath, in caseID: String) throws -> FigmaSVGOracle.Element? {
        try FigmaSVGOracle.paths(caseID).first { FigmaSVGOracle.matches(path.commands, $0.commands) }
    }

    @Test("Every V1 vector network reproduces its exported path within 0.01 pt", arguments: [
        "V1a closed filled triangle", "V1c flattened donut", "V1d star nonzero", "V1d star evenodd",
        "V1f compound", "V1g open curves", "V1h line",
    ])
    func v1Networks(name: String) throws {
        let (path, _) = try Self.fillPath(name, in: "V1")
        #expect(try Self.element(matching: path, in: "V1") != nil, "\(name): \(path.commands)")
    }

    @Test("A region's winding rule is the exported path's fill rule", arguments: [
        ("V1a closed filled triangle", FigmaWindingRule.nonzero),
        ("V1c flattened donut", .evenOdd),
        ("V1d star nonzero", .nonzero),
        ("V1d star evenodd", .evenOdd),
        ("V1f compound", .nonzero),
    ])
    func fillRules(name: String, rule: FigmaWindingRule) throws {
        let (path, network) = try Self.fillPath(name, in: "V1")
        #expect(network.regions.map(\.windingRule) == [rule])
        let found = try Self.element(matching: path, in: "V1")
        let element = try #require(found)
        #expect((element.attributes["fill-rule"] == "evenodd") == (rule == .evenOdd), "\(name)")
    }

    @Test("A curved segment's tangents give the exported cubic's control points")
    func donutTangents() throws {
        let node = try Blobs.node("V1c flattened donut", in: "V1")
        let index = try #require(node["vectorData"]?["vectorNetworkBlob"]?.uintValue)
        let network = try FigmaBlobTable(message: Blobs.message("V1")).vectorNetwork(at: index)
        let first = network.segments[0]
        #expect(first.tangentStart == FigmaPoint(x: Double(Float(bitPattern: 0x41DC_E9F5)), y: 0))
        #expect(first.tangentEnd == FigmaPoint(x: 0, y: Double(Float(bitPattern: 0xC1DC_E9F5))))
        // The SVG's first cubic, `C377.614 30 400 52.3858 400 80`, less the node's (300, 30).
        #expect(abs(first.tangentStart.x - 27.614) < 0.001)
        #expect(network.regions[0].loops == [[0, 1, 2, 3], [4, 5, 6, 7]])
    }

    @Test("P1's stroked networks, one blob shared by several nodes, match the export", arguments: [
        "P1d cap ROUND", "P1d cap SQUARE", "P1d join BEVEL", "P1d join ROUND",
    ])
    func p1Networks(name: String) throws {
        let (path, _) = try Self.fillPath(name, in: "P1")
        #expect(try Self.element(matching: path, in: "P1") != nil, "\(name): \(path.commands)")
    }

    /// T1d is left out: the export splits mixed-style text into one path per fill.
    @Test("A text node's glyph outlines, placed at their glyph positions, draw the exported text", arguments: [
        "T1a simple", "T1b two lines", "T1f script cjk", "T1f script arabic",
    ])
    func glyphOutlines(name: String) throws {
        let node = try Blobs.node(name, in: "T1")
        let offset = try Self.offset(node)
        let table = try FigmaBlobTable(message: Blobs.message("T1"))
        var commands: [FigmaPathCommand] = []
        for glyph in try #require(node["derivedTextData"]?["glyphs"]?.arrayValue) {
            let size = try Double(#require(glyph["fontSize"]?.floatValue))
            let x = try offset.x + Double(#require(glyph["position"]?["x"]?.floatValue))
            // Figma's SVG export snaps each baseline to a whole point; the glyph keeps the
            // unrounded one (31.136 in T1a), so the oracle rounds it too.
            let y = try offset.y + Double(#require(glyph["position"]?["y"]?.floatValue)).rounded()
            let outline = try table.path(at: #require(glyph["commandsBlob"]?.uintValue))
            commands += outline.mapped { FigmaPoint(x: x + $0.x * size, y: y - $0.y * size) }.commands
        }
        let path = FigmaPath(commands: commands)
        #expect(!commands.isEmpty)
        #expect(try Self.element(matching: path, in: "T1") != nil, "\(name)")
    }

    @Test("Every glyph of every text node decodes, and its text content comes from textData", arguments: ["T1", "C1", "R1"])
    func textContentIsIndependent(caseID: String) throws {
        let message = try Blobs.message(caseID)
        let table = try FigmaBlobTable(message: message)
        for node in message["nodeChanges"]?.arrayValue ?? [] where node["type"]?.enumName == "TEXT" {
            let characters = node["textData"]?["characters"]?.stringValue
            #expect(characters?.isEmpty == false, "\(node["name"]?.stringValue ?? "?")")
            for glyph in node["derivedTextData"]?["glyphs"]?.arrayValue ?? [] {
                _ = try table.path(at: #require(glyph["commandsBlob"]?.uintValue))
            }
        }
        #expect(try Blobs.node("T1a simple", in: "T1")["textData"]?["characters"]?.stringValue == "Fixture text")
        #expect(try Blobs.node("T1f script emoji", in: "T1")["textData"]?["characters"]?.stringValue == "😀")
    }

    @Test("An emoji glyph has an empty outline; its picture is not in the blob")
    func emojiGlyph() throws {
        let node = try Blobs.node("T1f script emoji", in: "T1")
        let glyph = try #require(node["derivedTextData"]?["glyphs"]?.arrayValue?.first)
        let table = try FigmaBlobTable(message: Blobs.message("T1"))
        let blob = try table.blob(at: #require(glyph["commandsBlob"]?.uintValue))
        #expect(blob == Data([0]))
        #expect(try FigmaPath(blob: blob).commands.isEmpty)
    }

    @Test("An instance's fillGeometry Path uses the same command stream, in the node's points")
    func pathGeometry() throws {
        let node = try Blobs.node("C1c instance", in: "C1")
        let paths = node["derivedSymbolData"]?.arrayValue?.compactMap { $0["fillGeometry"]?.arrayValue?.first } ?? []
        let geometry = try #require(paths.first)
        #expect(FigmaWindingRule(rawValue: geometry["windingRule"]?.enumName ?? "") == .nonzero)
        let table = try FigmaBlobTable(message: Blobs.message("C1"))
        let path = try table.path(at: #require(geometry["commandsBlob"]?.uintValue))
        #expect(path.commands == [
            .move(to: .zero),
            .line(to: FigmaPoint(x: 40, y: 0)),
            .line(to: FigmaPoint(x: 40, y: 40)),
            .line(to: FigmaPoint(x: 0, y: 40)),
            .line(to: .zero),
            .close,
        ])
    }
}
