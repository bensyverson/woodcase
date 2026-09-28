//
//  DocumentLinterCollapsedTextTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `collapsed-text`: a text node whose settled width or height is zero because its
/// `textGrowth` holds that axis to `kind.width`/`kind.height` and the sizing has
/// nothing to fall back on.
@MainActor
struct DocumentLinterCollapsedTextTests {
    // MARK: - Helpers

    private static let content = "Nanoshoot"

    /// A text node with the given box and growth. `width`/`height` of `nil` is a bare
    /// `fit_content` with no fallback — the same default the layout engine applies to
    /// an absent `kind.width`/`kind.height`.
    private func text(
        _ id: String,
        name: String,
        width: PenSizing?,
        height: PenSizing?,
        growth: PenTextGrowth?,
        content: String = content
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

    private func collapsedFindings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .collapsedText }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is collapsed-text")
    func checkIsAWarning() {
        #expect(LintCheck.collapsedText.rawValue == "collapsed-text")
        #expect(LintCheck.collapsedText.severity == .warning)
        #expect(!LintCheck.collapsedText.summary.isEmpty)
    }

    // MARK: - Findings

    @Test("fixed-width growth with a bare fit_content width collapses to a finding")
    func fixedWidthWithFitContentWidthIsAFinding() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: .fixed(20), growth: .fixedWidth),
        ])
        let findings = try collapsedFindings(doc)
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.nodeID == "Txt01")
        #expect(finding.severity == .warning)
    }

    @Test("The finding names the growth-and-width pair the node has")
    func findingNamesTheCollapsingPair() throws {
        let doc = board([
            text("Txt01", name: "Label", width: .fitContent(fallback: nil), height: .fixed(20), growth: .fixedWidth),
        ])
        let finding = try #require(try collapsedFindings(doc).first)
        #expect(finding.message.contains("kind.textGrowth=fixed-width"))
        #expect(finding.message.contains("kind.width=fit_content"))
    }

    @Test("The finding's remedy is a numeric width, or a growth that lets width follow the text")
    func findingNamesTheRemedy() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: .fixed(20), growth: .fixedWidth),
        ])
        let finding = try #require(try collapsedFindings(doc).first)
        #expect(finding.message.contains("kind.width="))
        #expect(finding.message.contains("kind.textGrowth=auto"))
        #expect(finding.message.contains("woodcase set <file> Txt01"))
    }

    @Test("fixed-width-height growth with a bare fit_content height collapses to a finding")
    func fixedWidthHeightWithFitContentHeightIsAFinding() throws {
        let doc = board([
            text("Txt01", name: "Label", width: .fixed(100), height: nil, growth: .fixedWidthHeight),
        ])
        let finding = try #require(try collapsedFindings(doc).first)
        #expect(finding.message.contains("kind.textGrowth=fixed-width-height"))
        #expect(finding.message.contains("kind.height=fit_content"))
        #expect(finding.message.contains("kind.height="))
        #expect(finding.message.contains("kind.textGrowth=auto"))
    }

    @Test("Both axes collapsing under fixed-width-height is one finding naming both")
    func bothAxesCollapseIsOneFindingNamingBoth() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: nil, growth: .fixedWidthHeight),
        ])
        let findings = try collapsedFindings(doc)
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.message.contains("kind.width=fit_content"))
        #expect(finding.message.contains("kind.height=fit_content"))
    }

    @Test("auto growth never collapses: both axes measure from the text")
    func autoGrowthIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: nil, growth: .auto),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("No growth declared behaves like auto: nothing collapses")
    func nilGrowthIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: nil, growth: nil),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("fixed-width growth with a numeric width is clean")
    func fixedWidthWithNumericWidthIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: .fixed(100), height: .fixed(20), growth: .fixedWidth),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("A fit_content width with a fallback is clean: the engine has something to fall back on")
    func fitContentWithFallbackIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: .fitContent(fallback: 200), height: .fixed(20), growth: .fixedWidth),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("fixed-width-height growth with numeric width and height is clean")
    func fixedWidthHeightWithNumbersIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: .fixed(100), height: .fixed(40), growth: .fixedWidthHeight),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("Empty content never collapses")
    func emptyContentIsClean() throws {
        let doc = board([
            text("Txt01", name: "Label", width: nil, height: .fixed(20), growth: .fixedWidth, content: ""),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }

    @Test("A non-text node is never a collapsed-text finding")
    func nonTextIsClean() throws {
        let doc = board([
            PenNode(
                id: "Rec01",
                common: PenNodeCommon(name: "Box", x: .literal(0), y: .literal(0)),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(0), height: .fixed(10)))
            ),
        ])
        #expect(try collapsedFindings(doc).isEmpty)
    }
}
