//
//  DocumentLinterTextOverflowTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `text-overflow`: a text node whose box is taller than nothing the content can push,
/// and shorter than the content needs.
@MainActor
struct DocumentLinterTextOverflowTests {
    // MARK: - Helpers

    /// The paragraph every overflowing case uses: long enough to wrap several times at
    /// 100 points, so no font substitution can make it fit a 20-point box.
    private static let paragraph = """
    The quick brown fox jumps over the lazy dog, and then it jumps back again \
    because the dog was not paying attention the first time.
    """

    /// A text node with the given box and growth.
    private func text(
        _ id: String,
        name: String,
        width: PenSizing?,
        height: PenSizing?,
        growth: PenTextGrowth?,
        content: String = paragraph
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, x: .literal(0), y: .literal(0)),
            kind: .text(PenNode.TextData(
                width: width,
                height: height,
                content: .literal(content),
                textGrowth: growth,
                fontSize: .literal(16)
            ))
        )
    }

    /// A 400×400 absolute artboard holding the given children.
    private func board(_ children: [PenNode]) -> EditableDocument {
        EditableDocument(from: PenDocument(children: [
            PenNode(
                id: "Brd01",
                common: PenNodeCommon(name: "Board", x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(400), height: .fixed(400),
                    layout: PenLayoutDirection.none, children: children
                ))
            ),
        ]))
    }

    private func overflowFindings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .textOverflow }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is text-overflow")
    func checkIsAWarning() {
        #expect(LintCheck.textOverflow.rawValue == "text-overflow")
        #expect(LintCheck.textOverflow.severity == .warning)
        #expect(!LintCheck.textOverflow.summary.isEmpty)
    }

    // MARK: - Findings

    @Test("A fixed box too short for its content is one finding")
    func fixedBoxTooShortIsAFinding() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(20), growth: .fixedWidthHeight),
        ])
        let findings = try overflowFindings(doc)
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.nodeID == "Txt01")
        #expect(finding.severity == .warning)
    }

    @Test("The finding names the overflow, the box and the height the content needs, in points")
    func findingNamesThePoints() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(20), growth: .fixedWidthHeight),
        ])
        let finding = try #require(try overflowFindings(doc).first)
        let needed = PenTextMeasurer.measure(Self.paragraph, fontSize: 16, maxWidth: 100).height
        #expect(finding.message.contains("\(Int(needed.rounded(.up)))pt"))
        #expect(finding.message.contains("20pt"))
        #expect(finding.message.contains("\(Int((needed - 20).rounded(.up)))pt"))
    }

    @Test("The finding's remedy is a bigger box or a growing one, by property path")
    func findingNamesTheRemedy() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(20), growth: .fixedWidthHeight),
        ])
        let finding = try #require(try overflowFindings(doc).first)
        #expect(finding.message.contains("kind.height="))
        #expect(finding.message.contains("kind.textGrowth=fixed-width"))
        #expect(finding.message.contains("woodcase set <file> Txt01"))
    }

    @Test("A box tall enough for its content is clean")
    func boxThatFitsIsClean() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(400), growth: .fixedWidthHeight),
        ])
        #expect(try overflowFindings(doc).isEmpty)
    }

    @Test("A height that sizes to content is never an overflow — the box grows")
    func fitContentHeightIsClean() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: nil, growth: .fixedWidth),
        ])
        #expect(try overflowFindings(doc).isEmpty)
    }

    @Test("A fixed height on an auto-growth node still overflows: growth alone does not size it")
    func fixedHeightWithoutFixedGrowthIsAFinding() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(20), growth: PenTextGrowth.auto),
        ])
        #expect(try overflowFindings(doc).count == 1)
    }

    @Test("Empty content never overflows")
    func emptyContentIsClean() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(100), height: .fixed(20), growth: .fixedWidthHeight, content: ""),
        ])
        #expect(try overflowFindings(doc).isEmpty)
    }

    @Test("A zero-width box is not measured: there is no wrap width to measure against")
    func zeroWidthIsSkipped() throws {
        let doc = board([
            text("Txt01", name: "Body", width: .fixed(0), height: .fixed(20), growth: .fixedWidthHeight),
        ])
        #expect(try overflowFindings(doc).isEmpty)
    }

    @Test("A non-text node is never an overflow")
    func nonTextIsClean() throws {
        let doc = board([
            PenNode(
                id: "Rec01",
                common: PenNodeCommon(name: "Box", x: .literal(0), y: .literal(0)),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
            ),
        ])
        #expect(try overflowFindings(doc).isEmpty)
    }
}
