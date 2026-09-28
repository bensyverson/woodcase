//
//  DocumentLinterDuplicateNameTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `duplicate-name`: one finding per node whose name an earlier **sibling** in the
/// linted scope already holds.
@MainActor
struct DocumentLinterDuplicateNameTests {
    // MARK: - Helpers

    /// A frame node, optionally with children, at the given name and origin.
    private func frame(
        _ id: String,
        name: String?,
        x: Double = 0,
        y: Double = 0,
        children: [PenNode] = []
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, x: .literal(x), y: .literal(y)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(10), height: .fixed(10), layout: PenLayoutDirection.none,
                children: children.isEmpty ? nil : children
            ))
        )
    }

    private func document(_ roots: [PenNode]) -> EditableDocument {
        EditableDocument(from: PenDocument(children: roots))
    }

    private func duplicateFindings(_ document: EditableDocument, root: String? = nil) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document, root: root).filter { $0.check == .duplicateName }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is duplicate-name")
    func checkIsAWarning() {
        #expect(LintCheck.duplicateName.rawValue == "duplicate-name")
        #expect(LintCheck.duplicateName.severity == .warning)
        #expect(!LintCheck.duplicateName.summary.isEmpty)
    }

    // MARK: - Findings

    @Test("Two siblings sharing a name are one finding, named on the later of the two")
    func twoNodesSharingANameAreOneFinding() throws {
        let doc = document([
            frame("Fl001", name: "FL-TopBar"),
            frame("Fl002", name: "FL-TopBar"),
        ])
        let findings = try duplicateFindings(doc)
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.nodeID == "Fl002")
        #expect(finding.severity == .warning)
    }

    @Test("The finding names the shared name, both ids and both paths")
    func findingNamesBothNodes() throws {
        let doc = document([
            frame("Fl001", name: "FL-TopBar"),
            frame("Fl002", name: "FL-TopBar"),
        ])
        let finding = try #require(try duplicateFindings(doc).first)
        #expect(finding.message.contains("FL-TopBar"))
        #expect(finding.message.contains("Fl001"))
        #expect(finding.message.contains("Fl002"))
        #expect(finding.path == "FL-TopBar")
        let firstPath = try #require(doc.namePath(of: "Fl001"))
        #expect(finding.message.contains(firstPath))
    }

    @Test("The finding says the collision is between siblings, and that a cousin is fine")
    func findingSaysSibling() throws {
        let doc = document([
            frame("Par01", name: "Parent", children: [
                frame("Fl001", name: "TopBar"),
                frame("Fl002", name: "TopBar"),
            ]),
        ])
        let finding = try #require(try duplicateFindings(doc).first)
        #expect(finding.message.contains("sibling"))
        #expect(finding.message.contains("different parents"))
    }

    @Test("Three siblings sharing a name are two findings, both against the first")
    func threeNodesSharingANameAreTwoFindings() throws {
        let doc = document([
            frame("Fl001", name: "FL-TopBar"),
            frame("Fl002", name: "FL-TopBar"),
            frame("Fl003", name: "FL-TopBar"),
        ])
        let findings = try duplicateFindings(doc)
        #expect(findings.map(\.nodeID) == ["Fl002", "Fl003"])
        for finding in findings {
            #expect(finding.message.contains("Fl001"))
        }
    }

    @Test("Two same-named cousins are not a finding: one more segment tells them apart")
    func duplicatesAcrossDifferentParentsAreNotFlagged() throws {
        let doc = document([
            frame("Par01", name: "Files", children: [frame("Fl001", name: "TopBar")]),
            frame("Par02", name: "Following", children: [frame("Fl002", name: "TopBar")]),
        ])
        #expect(try duplicateFindings(doc).isEmpty)
    }

    @Test("A name shared with a node at another depth is not a finding either")
    func duplicateAcrossDepthsIsNotFlagged() throws {
        let doc = document([
            frame("Par01", name: "TopBar", children: [frame("Fl001", name: "TopBar")]),
        ])
        #expect(try duplicateFindings(doc).isEmpty)
    }

    @Test("Unnamed nodes never collide")
    func unnamedNodesNeverCollide() throws {
        let doc = document([
            frame("Un001", name: nil),
            frame("Un002", name: nil),
        ])
        #expect(try duplicateFindings(doc).isEmpty)
    }

    @Test("Distinct names are clean")
    func distinctNamesAreClean() throws {
        let doc = document([
            frame("Aa001", name: "Alpha"),
            frame("Bb001", name: "Beta"),
        ])
        #expect(try duplicateFindings(doc).isEmpty)
    }

    @Test("A lint scoped to a subtree only reports a duplicate wholly inside it")
    func scopedLintOnlyReportsDuplicatesInScope() throws {
        let doc = document([
            frame("Par01", name: "Parent", children: [
                frame("Fl001", name: "TopBar"),
                frame("Fl002", name: "TopBar"),
            ]),
        ])
        // Unscoped: both TopBars are siblings in the listing.
        #expect(try duplicateFindings(doc).count == 1)
        // Scoped to one of them: only one TopBar is in the listing at all.
        #expect(try duplicateFindings(doc, root: "#Fl001").isEmpty)
    }

    @Test("Findings come back in document order, mixed in among every other check")
    func findingsAreInDocumentOrder() throws {
        let doc = document([
            frame("Aa001", name: "Alpha"),
            frame("Fl001", name: "FL-TopBar"),
            frame("Bb001", name: "Beta"),
            frame("Fl002", name: "FL-TopBar"),
        ])
        #expect(try duplicateFindings(doc).map(\.nodeID) == ["Fl002"])
    }

    @Test("Two roots sharing a name are siblings under the document root")
    func rootsAreSiblings() throws {
        let doc = document([
            frame("Rt001", name: "Board"),
            frame("Rt002", name: "Board"),
        ])
        #expect(try duplicateFindings(doc).map(\.nodeID) == ["Rt002"])
    }

    @Test("A clean document produces no duplicate-name finding")
    func cleanDocumentIsClean() throws {
        let doc = document([
            frame("Aa001", name: "Alpha", children: [frame("Aa002", name: "Inner")]),
            frame("Bb001", name: "Beta", children: [frame("Bb002", name: "Inner Beta")]),
        ])
        #expect(try duplicateFindings(doc).isEmpty)
    }
}
