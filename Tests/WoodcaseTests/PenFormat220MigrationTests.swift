//
//  PenFormat220MigrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers reading and writing around format 2.20, which Pen 1.2.15 writes: the model is
/// 2.20, a 2.19 file gets only the 2.20 image-mode upgrade — never the 2.19 shadow rule
/// again — and an older file gets both, in version order.
///
/// The rule's every location is covered at the JSON level by
/// ``PenImageModeMigrationRuleTests``; these tests run whole documents through the parser.
struct PenFormat220MigrationTests {
    // MARK: - Helpers

    private func document(version: String, children: String) -> Data {
        Data(#"{"version":"\#(version)","children":\#(children)}"#.utf8)
    }

    private func rectangle(_ node: PenNode) throws -> PenNode.RectangleData {
        guard case let .rectangle(data) = node.kind else {
            Issue.record("\(node.id) is not a rectangle")
            throw CancellationError()
        }
        return data
    }

    private func shadow(of node: PenNode) throws -> PenEffect.PenShadowEffect {
        guard case let .shadow(shadow)? = try rectangle(node).effects?.all.first else {
            Issue.record("\(node.id) has no shadow")
            throw CancellationError()
        }
        return shadow
    }

    private func imageMode(of node: PenNode) throws -> PenImageFillMode? {
        guard case let .image(image)? = try rectangle(node).fills?.all.first else {
            Issue.record("\(node.id) has no image fill")
            throw CancellationError()
        }
        return image.mode
    }

    /// A rectangle with an inner shadow carrying a spread, and an image fill with no mode.
    private let shadowAndImage = #"""
    [{"id":"R1","type":"rectangle","width":10,"height":10,
      "fill":{"type":"image","url":"./a.png"},
      "effect":{"type":"shadow","shadowType":"inner","color":"#000000","blur":4,"spread":3}}]
    """#

    // MARK: - The version

    @Test("The model writes format 2.20, and 2.20 is a version Pen has been seen to write")
    func currentVersionIs220() {
        #expect(PenFormatVersion.current == PenFormatVersion(major: 2, minor: 20))
        #expect(PenDocument.currentFormatVersion == "2.20")
        #expect(PenFormatVersion.observedModern.contains(PenFormatVersion(major: 2, minor: 20)))
    }

    @Test("A 2.20 file reads with no diagnostic and keeps its version")
    func format220ReadsQuietly() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.20", children: shadowAndImage), diagnostics: diagnostics)
        #expect(doc.version == "2.20")
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .inner)
        #expect(try imageMode(of: node) == nil)
    }

    // MARK: - A 2.19 file

    @Test("A 2.19 inner shadow with a spread stays inner when read by the 2.20 model, silently")
    func format219KeepsItsInnerShadow() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.19", children: shadowAndImage), diagnostics: diagnostics)
        #expect(doc.version == "2.20")
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .inner)
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    @Test("A 2.19 image with no mode reads as an explicit stretch, which is what 2.19 meant")
    func format219MissingModeIsStretch() throws {
        let children = #"[{"id":"R1","type":"rectangle","width":10,"height":10,"fill":{"type":"image","url":"./a.png"}}]"#
        let doc = try PenParser.parse(document(version: "2.19", children: children))
        #expect(try imageMode(of: #require(doc.children.first)) == .stretch)
    }

    @Test("A 2.19 file survives a write by the 2.20 model with its inner shadow and its stretch")
    func format219RoundTrip() throws {
        let outcome = try PenFileMigrator.migrate(document(version: "2.19", children: shadowAndImage))
        #expect(!outcome.wasAlreadyCurrent)
        #expect(outcome.writtenVersion == "2.20")
        let reread = try PenParser.parse(outcome.data)
        let node = try #require(reread.children.first)
        #expect(try shadow(of: node).shadowType == .inner)
        #expect(try imageMode(of: node) == .stretch)
    }

    @Test("A 2.19 file's fill and fit modes read as cover and contain, and are written that way")
    func format219RenamedModesEndToEnd() throws {
        let children = #"""
        [{"id":"F1","type":"rectangle","width":10,"height":10,"fill":{"type":"image","url":"./a.png","mode":"fill"}},
         {"id":"F2","type":"rectangle","width":10,"height":10,"fill":{"type":"image","url":"./a.png","mode":"fit"}}]
        """#
        let outcome = try PenFileMigrator.migrate(document(version: "2.19", children: children))
        let written = String(decoding: outcome.data, as: UTF8.self)
        #expect(written.contains(#""cover""#) && written.contains(#""contain""#))
        #expect(!written.contains(#""fill" : "fill""#) && !written.contains(#""fit""#))
        let reread = try PenParser.parse(outcome.data)
        #expect(try imageMode(of: reread.children[0]) == .cover)
        #expect(try imageMode(of: reread.children[1]) == .contain)
    }

    @Test("A 2.20 image with no mode is placed as cover, the 2.20 default")
    func format220MissingModeIsCover() throws {
        let children = #"[{"id":"R1","type":"rectangle","width":10,"height":10,"fill":{"type":"image","url":"./a.png"}}]"#
        let doc = try PenParser.parse(document(version: "2.20", children: children))
        guard case let .image(image)? = try rectangle(#require(doc.children.first)).fills?.all.first else {
            Issue.record("no image fill")
            return
        }
        #expect(image.mode == nil)
        #expect(image.placement == .cover)
    }

    // MARK: - An older file

    @Test("A 2.17 file gets the 2.19 shadow rule and then the 2.20 image rule",
          arguments: ["2.17", "2.9"])
    func olderFileGetsBothRules(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: shadowAndImage), diagnostics: diagnostics)
        #expect(doc.version == "2.20")
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .outer)
        #expect(try imageMode(of: node) == .stretch)
        #expect(diagnostics.diagnostics.contains { $0.message.contains("inner") && $0.nodeID == "R1" })
    }
}
