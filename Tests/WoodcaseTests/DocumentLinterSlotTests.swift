//
//  DocumentLinterSlotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What `lint` says about a slot frame.
///
/// A slot is a hole a component leaves for its instances to fill, so it is empty in
/// the definition by design — `empty-fit-content` on one is the check firing at the
/// feature rather than at a fault.
@MainActor
struct DocumentLinterSlotTests {
    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: base, withExtension: ext, subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    private func document(_ fixture: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: fixtureURL(fixture)))
    }

    @Test("An empty slot frame that sizes to content is not an empty-fit-content finding")
    func slotFramesAreExempt() throws {
        let findings = try DocumentLinter.findings(in: document("slot-fill.pen"))
        #expect(!findings.contains { $0.check == .emptyFitContent && $0.nodeID == "CSlt0" })
    }

    @Test("A childless frame that is not a slot still reports empty-fit-content")
    func plainFramesStillFire() throws {
        let findings = try DocumentLinter.findings(in: document("slot-fill.pen"))
        #expect(findings.contains { $0.check == .emptyFitContent && $0.nodeID == "Hole0" })
    }
}
