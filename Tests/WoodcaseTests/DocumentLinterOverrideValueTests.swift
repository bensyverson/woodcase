//
//  DocumentLinterOverrideValueTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Since d893dd0 the write path refuses an override whose value the descendant it
/// patches cannot decode, whose key names no descendant, or whose property is a
/// dotted path rather than a raw .pen key — but a file that already carries one,
/// from an import or from Pen.app, never went through that guard. Expansion stays
/// tolerant on purpose (``PenNodePatcher/patchNode(_:with:)`` falls back to the
/// unpatched node), so nothing else says the override in the file never draws. These
/// three lint checks are that report.
@MainActor
struct DocumentLinterOverrideValueTests {
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

    private func findings(_ name: String) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document(name))
    }

    // MARK: - override-value-rejected

    @Test("A value the descendant cannot decode is a finding, naming the key and node")
    func undecodableValueIsReported() throws {
        let tripped = try findings("override-value-rejected.pen").filter { $0.check == .overrideValueRejected }
        #expect(tripped.map(\.nodeID) == ["Rf001"])
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("content") == true)
        #expect(tripped.first?.message.contains(NodePropertyCodec.expectedShape(of: "content")) == true)
    }

    @Test("A value the descendant can decode is not a finding")
    func decodableValueIsClean() throws {
        let findings = try findings("override-value-rejected.pen")
        #expect(findings.filter { $0.check == .overrideValueRejected && $0.nodeID == "Rf002" }.isEmpty)
    }

    @Test("An object replacement carrying a type key is exempt from value checking")
    func objectReplacementIsExempt() throws {
        let findings = try findings("override-value-rejected.pen")
        #expect(findings.filter { $0.check == .overrideValueRejected && $0.nodeID == "Rf003" }.isEmpty)
    }

    @Test("A ref whose component is not in the registry is exempt from value checking")
    func unresolvedComponentIsExempt() throws {
        let findings = try findings("override-value-rejected.pen")
        #expect(findings.filter { $0.check == .overrideValueRejected && $0.nodeID == "Rf004" }.isEmpty)
        // It is still reported as a broken ref — just not double-reported here.
        #expect(findings.contains { $0.check == .brokenRef && $0.nodeID == "Rf004" })
    }

    @Test("Exactly one override-value-rejected finding comes from the fixture's one bad value")
    func onlyTheBadValueTrips() throws {
        let tripped = try findings("override-value-rejected.pen").filter { $0.check == .overrideValueRejected }
        #expect(tripped.count == 1)
    }

    // MARK: - override-target-not-found

    @Test("A descendants key naming a real descendant is not a finding")
    func realDescendantKeyIsClean() throws {
        let tripped = try findings("override-target-not-found.pen").filter { $0.check == .overrideTargetNotFound }
        #expect(tripped.map(\.nodeID) == ["Rf002"])
    }

    @Test("A descendants key naming nothing in the component is a finding")
    func unknownDescendantKeyIsReported() throws {
        let tripped = try findings("override-target-not-found.pen").filter { $0.check == .overrideTargetNotFound }
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("NoSuch") == true)
    }

    // MARK: - override-key-unread

    @Test("A property stored under a dotted path rather than a raw key is a finding")
    func dottedKeyIsReported() throws {
        let tripped = try findings("override-key-unread.pen").filter { $0.check == .overrideKeyUnread }
        #expect(tripped.map(\.nodeID) == ["Rf001"])
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("kind.content") == true)
        #expect(tripped.first?.message.contains("content") == true)
    }

    @Test("A property stored under its raw .pen key is not a finding")
    func rawKeyIsClean() throws {
        let findings = try findings("override-key-unread.pen")
        #expect(findings.filter { $0.check == .overrideKeyUnread && $0.nodeID == "Rf002" }.isEmpty)
    }
}
