//
//  DocumentLinterRefOverrideTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `unresolved-variable` on a `ref`: expansion replaces the instance before the
/// resolver reaches its override maps, so the linter has to resolve the authored ref
/// itself. A `$name` the document defines must lint clean wherever it is overridden;
/// one it does not define must still be reported.
@MainActor
struct DocumentLinterRefOverrideTests {
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

    private func unresolved(_ name: String) throws -> [LintFinding] {
        try findings(name).filter { $0.check == .unresolvedVariable }
    }

    // MARK: - A defined variable in an override

    @Test("A defined variable in a ref's root overrides is not a finding")
    func definedVariableInRootOverrideIsClean() throws {
        #expect(try unresolved("ref-root-override-clean.pen").isEmpty)
        #expect(try findings("ref-root-override-clean.pen").isEmpty)
    }

    @Test("A defined variable in a ref's descendant overrides is not a finding")
    func definedVariableInDescendantOverrideIsClean() throws {
        #expect(try unresolved("ref-descendant-override-clean.pen").isEmpty)
        #expect(try findings("ref-descendant-override-clean.pen").isEmpty)
    }

    @Test("A defined variable overridden on a ref inside a component is not a finding")
    func definedVariableInNestedInstanceOverrideIsClean() throws {
        #expect(try unresolved("ref-nested-instance-clean.pen").isEmpty)
        #expect(try findings("ref-nested-instance-clean.pen").isEmpty)
    }

    // MARK: - An undefined variable in an override

    @Test("A variable the document does not define is still a finding in a root override")
    func undefinedVariableInRootOverrideIsReported() throws {
        let tripped = try unresolved("ref-root-override-trips.pen")
        #expect(tripped.map(\.nodeID) == ["Rf001"])
        #expect(tripped.first?.severity == .error)
        #expect(tripped.first?.message.contains("$brnad") == true)
    }

    // MARK: - The plain case is untouched

    @Test("A plain unresolved variable on an ordinary node is still a finding")
    func undefinedVariableOnPlainNodeIsReported() throws {
        let tripped = try unresolved("unresolved-variable-trips.pen")
        #expect(tripped.map(\.nodeID) == ["Bx001"])
        #expect(tripped.first?.message.contains("$brand") == true)
    }
}
