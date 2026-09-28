//
//  DocumentLinterCollapsedAbsoluteFrameTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `collapsed-absolute-frame`: a `layout: "none"` frame with children whose width or
/// height is `fit_content` with no fallback (or a fallback of 0), which Pen — and so
/// Woodcase — settles at 0 on that axis rather than around its children (leaf Jg0BOv).
@MainActor
struct DocumentLinterCollapsedAbsoluteFrameTests {
    // MARK: - Helpers

    /// An 80×40 rectangle at (10, 10).
    private func child(_ id: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Swatch", x: .literal(10), y: .literal(10)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(80), height: .fixed(40)))
        )
    }

    /// A frame with the given box and layout. `nil` sizes are absent — `fit_content`
    /// with no fallback, as the layout engine reads them.
    private func frame(
        _ id: String,
        width: PenSizing? = nil,
        height: PenSizing? = nil,
        layout: PenLayoutDirection? = PenLayoutDirection.none,
        children: [PenNode]
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Layer", x: .literal(50), y: .literal(50)),
            kind: .frame(PenNode.FrameData(width: width, height: height, layout: layout, children: children))
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

    private func findings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .collapsedAbsoluteFrame }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is collapsed-absolute-frame")
    func checkIsAWarning() {
        #expect(LintCheck.collapsedAbsoluteFrame.rawValue == "collapsed-absolute-frame")
        #expect(LintCheck.collapsedAbsoluteFrame.severity == .warning)
        #expect(!LintCheck.collapsedAbsoluteFrame.summary.isEmpty)
    }

    // MARK: - Findings

    @Test("A sizeless layout-none frame with children is one finding that says what 0×0 costs and how to fix it")
    func sizelessFrameIsAFinding() throws {
        let found = try findings(board([frame("Frm01", children: [child("Sw001")])]))
        #expect(found.count == 1)
        let finding = try #require(found.first)
        #expect(finding.nodeID == "Frm01")
        #expect(finding.severity == .warning)
        #expect(finding.message.contains("0×0"))
        #expect(finding.message.contains("fill"))
        #expect(finding.message.contains("clip"))
        #expect(finding.message.contains("flow"))
        #expect(finding.message.contains("woodcase set <file> Frm01 kind.width=<value> kind.height=<value>"))
    }

    @Test("Only the axis that collapses is named")
    func oneAxisIsNamed() throws {
        let found = try findings(board([frame("Frm01", height: .fixed(20), children: [child("Sw001")])]))
        let finding = try #require(found.first)
        #expect(finding.message.contains("0pt wide"))
        #expect(finding.message.contains("kind.width=<value>"))
        #expect(!finding.message.contains("kind.height=<value>"))
    }

    @Test("fit_content(0), the spelling Pen re-saves a missing size as, is a finding")
    func fitContentZeroIsAFinding() throws {
        let found = try findings(board([
            frame("Frm01", width: .fitContent(fallback: 0), height: .fitContent(fallback: 0), children: [child("Sw001")]),
        ]))
        #expect(found.count == 1)
    }

    // MARK: - Clean

    @Test("A fit_content fallback other than 0 is clean: the author chose the size")
    func nonZeroFallbackIsClean() throws {
        let found = try findings(board([
            frame("Frm01", width: .fitContent(fallback: 30), height: .fixed(20), children: [child("Sw001")]),
        ]))
        #expect(found.isEmpty)
    }

    @Test("A sized layout-none frame is clean")
    func sizedFrameIsClean() throws {
        let found = try findings(board([frame("Frm01", width: .fixed(100), height: .fixed(60), children: [child("Sw001")])]))
        #expect(found.isEmpty)
    }

    @Test("A sizeless layout-none frame with no children is left to empty-fit-content")
    func emptyFrameIsNotThisCheck() throws {
        #expect(try findings(board([frame("Frm01", children: [])])).isEmpty)
    }

    @Test("A flex frame sizes to its children, so a sizeless one is clean")
    func flexFrameIsClean() throws {
        #expect(try findings(board([frame("Frm01", layout: .horizontal, children: [child("Sw001")])])).isEmpty)
        #expect(try findings(board([frame("Frm02", layout: nil, children: [child("Sw002")])])).isEmpty)
    }

    @Test("A group sizes to its children's union, so it is clean")
    func groupIsClean() throws {
        let group = PenNode(
            id: "Grp01",
            common: PenNodeCommon(name: "Cluster", x: .literal(50), y: .literal(50)),
            kind: .group(PenNode.GroupData(children: [child("Sw001")]))
        )
        #expect(try findings(board([group])).isEmpty)
    }
}
