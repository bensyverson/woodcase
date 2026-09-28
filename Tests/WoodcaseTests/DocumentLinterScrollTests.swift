//
//  DocumentLinterScrollTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The scroll-aware half of `clipped`: `common.metadata._scroll` on a clipping frame
/// exempts overflow along the axis it declares, an undeclared clipping frame that
/// stacks its children folds an overflowing run into one teaching finding, and an
/// invalid `_scroll` value is its own warning. See `DocumentLinter+Scroll.swift`.
@MainActor
struct DocumentLinterScrollTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document(_ name: String) throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: "pen",
            subdirectory: "Fixtures/lint"
        ) else {
            throw FixtureLoadError.notFound(name)
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func clippedFindings(_ fixture: String) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document(fixture)).filter { $0.check == .clipped }
    }

    // MARK: - A declared axis

    @Test("A child overflowing only the declared axis is not a finding, however far it goes")
    func declaredAxisIsQuiet() throws {
        let findings = try clippedFindings("scroll-declared-axis.pen")
        #expect(!findings.contains { $0.nodeID == "Alg01" })
    }

    @Test("A child overflowing the cross axis keeps its finding, declared axis or not")
    func crossAxisStillTrips() throws {
        let findings = try clippedFindings("scroll-declared-axis.pen")
        #expect(findings.compactMap(\.nodeID).sorted() == ["Bth01", "Crs01"])
        for finding in findings {
            #expect(finding.message.contains("sits"))
            #expect(finding.message.contains("outside List"))
        }
    }

    @Test("A row fully inside its parent is never a finding, declared axis or not")
    func containedRowIsClean() throws {
        let findings = try clippedFindings("scroll-declared-axis.pen")
        #expect(!findings.contains { $0.nodeID == "Fin01" })
    }

    // MARK: - No declared axis: collapse onto the stacking axis

    @Test("Children overflowing only the frame's stacking axis collapse into one finding on the frame")
    func stackingAxisOverflowCollapses() throws {
        let findings = try clippedFindings("scroll-unannotated-collapse.pen")
        let collapsed = try #require(findings.first { $0.nodeID == "List1" })
        #expect(collapsed.message.contains("3 children"))
        #expect(collapsed.message.contains("120pt"))
        #expect(collapsed.message.contains("vertical axis"))
        #expect(collapsed.message.contains("List clips them"))
    }

    @Test("The collapsed children are not reported individually")
    func collapsedChildrenAreNotDuplicated() throws {
        let findings = try clippedFindings("scroll-unannotated-collapse.pen")
        #expect(!findings.contains { $0.nodeID == "Over1" })
        #expect(!findings.contains { $0.nodeID == "Over2" })
        #expect(!findings.contains { $0.nodeID == "Over3" })
    }

    @Test("A child overflowing the cross axis keeps its own finding, even in an unannotated frame")
    func crossAxisChildIsStillIndividual() throws {
        let findings = try clippedFindings("scroll-unannotated-collapse.pen")
        let wide = try #require(findings.first { $0.nodeID == "Wide1" })
        #expect(wide.message.contains("sits partly outside List"))
    }

    @Test("The collapsed finding proposes the deep-key _scroll command, which keeps the frame's other metadata")
    func collapsedFindingProposesTheCommand() throws {
        let findings = try clippedFindings("scroll-unannotated-collapse.pen")
        let collapsed = try #require(findings.first { $0.nodeID == "List1" })
        #expect(collapsed.message.contains("woodcase set <file> List common.metadata._scroll=vertical"))
    }

    @Test("clip:true alone, with no annotation and no stacking layout, changes nothing")
    func clipTrueFreeformIsUnchanged() throws {
        // Same shape as DocumentLinterTests.clippedChildren's clipped-trips.pen, plus
        // clip:true and no `_scroll`: a freeform (layout: none) frame has no stacking
        // axis to fold an overflow onto, so every child is still reported individually,
        // worded exactly as before.
        let findings = try clippedFindings("scroll-clip-true-freeform.pen")
        #expect(findings.map(\.nodeID) == ["Ovr02", "Out02"])
        #expect(findings.first?.message.contains("partly") == true)
        #expect(findings.dropFirst().first?.message.contains("entirely") == true)
    }

    // MARK: - An invalid `_scroll` value

    @Test("An invalid _scroll value is its own finding naming the valid values")
    func invalidScrollValueWarns() throws {
        let findings = try clippedFindings("scroll-invalid-value.pen")
        let invalid = try #require(findings.first { $0.nodeID == "List2" && $0.message.contains("diagonal") })
        #expect(invalid.message.contains("common.metadata._scroll=\"diagonal\""))
        #expect(invalid.message.contains("\"vertical\""))
        #expect(invalid.message.contains("\"horizontal\""))
        #expect(invalid.severity == .warning)
    }

    @Test("An invalid _scroll value falls back to the unannotated (collapsing) behaviour")
    func invalidScrollValueStillCollapses() throws {
        let findings = try clippedFindings("scroll-invalid-value.pen")
        let collapsed = try #require(findings.first {
            $0.nodeID == "List2" && $0.message.contains("children continue")
        })
        #expect(collapsed.message.contains("3 children"))
        #expect(!findings.contains { $0.nodeID == "Ovra2" })
        #expect(findings.contains { $0.nodeID == "Wide2" })
    }

    // MARK: - The check id

    @Test("Every scroll-aware finding still carries the clipped check id, so --exclude clipped drops it all")
    func everyFindingIsStillTheClippedCheck() throws {
        for fixture in ["scroll-declared-axis.pen", "scroll-unannotated-collapse.pen", "scroll-invalid-value.pen"] {
            let findings = try DocumentLinter.findings(in: document(fixture))
            #expect(findings.allSatisfy { $0.check == .clipped }, "\(fixture) produced a non-clipped finding")
        }
    }
}
