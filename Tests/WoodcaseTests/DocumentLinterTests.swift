//
//  DocumentLinterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct DocumentLinterTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String, subdirectory: String = "Fixtures/lint") throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: subdirectory) else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    private func document(_ fixture: String, subdirectory: String = "Fixtures/lint") throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: fixtureURL(fixture, subdirectory: subdirectory)))
    }

    private func findings(_ fixture: String) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document(fixture))
    }

    private func checks(_ findings: [LintFinding]) -> [LintCheck] {
        findings.map(\.check)
    }

    // MARK: - The clean document

    @Test("A clean document produces no findings at all")
    func cleanDocumentIsSilent() throws {
        #expect(try findings("clean.pen").isEmpty)
    }

    // MARK: - Text without fill

    @Test("A text node with no fill is a finding; the clean fixture's filled text is not")
    func textWithoutFill() throws {
        let tripped = try findings("text-without-fill-trips.pen")
        #expect(checks(tripped) == [.textWithoutFill])
        #expect(tripped.first?.nodeID == "Tx001")
        #expect(tripped.first?.severity == .warning)
        // Pen draws unfilled text as nothing (`render-text-unfilled.pen`), and so does Woodcase.
        #expect(tripped.first?.message.contains("draws nothing") == true)
        #expect(LintCheck.textWithoutFill.summary.contains("draws nothing"))

        let clean = try findings("clean.pen")
        #expect(!checks(clean).contains(.textWithoutFill))
    }

    // MARK: - fill_container inside a fit_content parent

    @Test("fill_container under a fit_content parent on the same axis is a finding")
    func fillContainerInFitParent() throws {
        let tripped = try findings("fill-in-fit-parent-trips.pen")
        // The fill gets Pen's 1-pt floor outside its 0-wide parent, as Pen lays it out, so
        // `clipped` reports the same node (`PenFlexFillMinimumTests`).
        #expect(checks(tripped) == [.fillContainerInFitParent, .clipped])
        #expect(tripped.first?.nodeID == "Bx001")
        #expect(tripped.first?.message.contains("width") == true)
        #expect(tripped.first?.message.contains("Root") == true)
    }

    @Test("A fill_container child of a fixed-size parent is not a finding")
    func fillContainerInSizedParentIsClean() throws {
        let clean = try findings("clean.pen")
        #expect(!checks(clean).contains(.fillContainerInFitParent))
    }

    // MARK: - fit_content with no children

    @Test("A childless fit_content container is a finding")
    func emptyFitContent() throws {
        let tripped = try findings("empty-fit-content-trips.pen")
        #expect(checks(tripped) == [.emptyFitContent])
        #expect(tripped.first?.nodeID == "Em001")
        #expect(tripped.first?.message.contains("width") == true)
    }

    @Test("A childless fit_content with a fallback is not a finding")
    func emptyFitContentWithFallbackIsClean() throws {
        let clean = try findings("clean.pen")
        #expect(!checks(clean).contains(.emptyFitContent))
    }

    // MARK: - Clipping

    @Test("A child crossing or outside its parent is a finding, and says which")
    func clippedChildren() throws {
        let tripped = try findings("clipped-trips.pen")
        #expect(checks(tripped) == [.clipped, .clipped])
        #expect(tripped.map(\.nodeID) == ["Ovr01", "Out01"])
        #expect(tripped.first?.message.contains("partly") == true)
        #expect(tripped.dropFirst().first?.message.contains("entirely") == true)
    }

    @Test("Nothing inside its parent is a clipping finding")
    func containedChildrenAreClean() throws {
        let clean = try findings("clean.pen")
        #expect(!checks(clean).contains(.clipped))
    }

    @Test("The clipping findings are exactly the rows `tree` flags as clipped")
    func clippingAgreesWithTreeRows() throws {
        for fixture in ["clipped-trips.pen", "clean.pen"] {
            let doc = try document(fixture)
            let flagged = try TreeView.rows(of: doc).filter { $0.clip != .none }.map(\.id)
            let linted = try DocumentLinter.findings(in: doc)
                .filter { $0.check == .clipped }
                .map(\.nodeID)
            #expect(linted == flagged, "clip disagreement in \(fixture)")
        }
    }

    @Test("The clip flag agreement holds for the tree leaf's own overflow fixture")
    func clippingAgreesOnTreeFixture() throws {
        let doc = try document("tree-overflow.pen", subdirectory: "Fixtures")
        let flagged = try TreeView.rows(of: doc).filter { $0.clip != .none }.map(\.id)
        let linted = try DocumentLinter.findings(in: doc)
            .filter { $0.check == .clipped }
            .map(\.nodeID)
        #expect(linted == flagged)
        #expect(flagged == ["Ovr01", "Out01"])
    }

    // MARK: - Broken refs

    @Test("A ref naming no component in the document is an error finding")
    func brokenRef() throws {
        let tripped = try findings("broken-ref-trips.pen")
        #expect(checks(tripped) == [.brokenRef])
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("Gone1") == true)
    }

    @Test("A ref that resolves is not a finding")
    func resolvingRefIsClean() throws {
        #expect(try findings("broken-ref-clean.pen").isEmpty)
    }

    // MARK: - Unresolved variables

    @Test("A reference left unresolved after variable resolution is an error finding")
    func unresolvedVariable() throws {
        let tripped = try findings("unresolved-variable-trips.pen")
        #expect(checks(tripped) == [.unresolvedVariable])
        #expect(tripped.first?.nodeID == "Bx001")
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("$brand") == true)
    }

    @Test("A defined variable resolves and is not a finding")
    func definedVariableIsClean() throws {
        #expect(try findings("unresolved-variable-clean.pen").isEmpty)
    }

    // MARK: - Unknown icons

    @Test("An icon renamed out from under the document is an error finding proposing the new name")
    func unknownIconProposesNearestName() throws {
        let tripped = try findings("unknown-icon-trips.pen")
        #expect(checks(tripped) == [.unknownIcon])
        #expect(tripped.first?.nodeID == "Ic001")
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("check-circle-2") == true)
        #expect(tripped.first?.message.contains("circle-check") == true)
    }

    @Test("An icon that resolves is not a finding")
    func knownIconIsClean() throws {
        #expect(try findings("unknown-icon-clean.pen").isEmpty)
    }

    @Test("An icon library this build does not know is an error finding listing the libraries")
    func unknownIconLibraryListsLibraries() throws {
        let tripped = try findings("unknown-icon-library-trips.pen")
        #expect(checks(tripped) == [.unknownIconLibrary])
        #expect(tripped.first?.nodeID == "Ic001")
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("font-awesome") == true)
        #expect(tripped.first?.message.contains("lucide") == true)
    }

    // MARK: - Pipeline diagnostics

    @Test("A pipeline diagnostic naming a node becomes a finding at that node's path")
    func pipelineDiagnosticForNode() throws {
        let diagnostic = PenDiagnostic(
            severity: .warning,
            stage: .fontResolution,
            message: "Font 'Manrope' could not be resolved; will fall back to SF Pro",
            nodeID: "Tx001"
        )
        let found = try DocumentLinter.findings(in: document("clean.pen"), diagnostics: [diagnostic])
        #expect(checks(found) == [.pipeline])
        #expect(found.first?.severity == .warning)
        #expect(found.first?.path == "Root/Label")
        #expect(found.first?.message.contains("fontResolution") == true)
        #expect(found.first?.message.contains("Manrope") == true)
    }

    @Test("A pipeline diagnostic naming no node is a document-level finding, reported first")
    func pipelineDiagnosticForDocument() throws {
        let diagnostic = PenDiagnostic(
            severity: .error,
            stage: .migration,
            message: "Format version 2.13 has never been observed in the wild",
            nodeID: nil
        )
        let found = try DocumentLinter.findings(
            in: document("clipped-trips.pen"), diagnostics: [diagnostic]
        )
        #expect(checks(found) == [.pipeline, .clipped, .clipped])
        #expect(found.first?.nodeID == nil)
        #expect(found.first?.path == nil)
        #expect(found.first?.severity == .error)
    }

    // MARK: - Paths, order and scope

    @Test("Every finding names its node by name path as well as by id")
    func findingsNameNodesByPath() throws {
        let tripped = try findings("clipped-trips.pen")
        #expect(tripped.map(\.path) == ["Root/Overflows", "Root/Outside"])
        #expect(tripped.map(\.nodeID) == ["Ovr01", "Out01"])
    }

    @Test("Findings come back in document order")
    func findingsAreInDocumentOrder() throws {
        let doc = try document("clipped-trips.pen")
        let order = try TreeView.rows(of: doc).map(\.id)
        let positions = try DocumentLinter.findings(in: doc)
            .compactMap(\.nodeID)
            .compactMap { order.firstIndex(of: $0) }
        #expect(positions == positions.sorted())
        #expect(positions.count == 2)
    }

    @Test("A root address scopes the lint to that subtree")
    func rootScopesTheLint() throws {
        let doc = try document("clipped-trips.pen")
        #expect(try DocumentLinter.findings(in: doc, root: "Root/Overflows").map(\.nodeID) == [])
        #expect(try DocumentLinter.findings(in: doc, root: "Root").map(\.nodeID) == ["Ovr01", "Out01"])
    }

    @Test("A root that names nothing is an error, not an empty listing")
    func unknownRootThrows() throws {
        let doc = try document("clean.pen")
        #expect(throws: EditingError.self) {
            _ = try DocumentLinter.findings(in: doc, root: "Nope")
        }
    }

    @Test("A scoped lint drops a document-level diagnostic that is outside the scope")
    func scopedLintDropsDocumentDiagnostics() throws {
        let diagnostic = PenDiagnostic(
            severity: .warning, stage: .migration, message: "legacy", nodeID: nil
        )
        let found = try DocumentLinter.findings(
            in: document("clipped-trips.pen"), root: "Root", diagnostics: [diagnostic]
        )
        #expect(checks(found) == [.clipped, .clipped])
    }
}
