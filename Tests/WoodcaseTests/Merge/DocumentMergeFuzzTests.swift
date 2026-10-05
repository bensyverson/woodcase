//
//  DocumentMergeFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``DocumentMerge`` under seeded random edits: both sides edit one base with
/// ``RandomEditGenerator``'s merge set, and the merge's operations must apply to ours
/// without a refusal, satisfy ``MergeOracle`` key by key, and come back empty on a
/// second merge. With one side left as the base the merge must reproduce the other, and
/// with edits confined to disjoint subtrees it must equal replaying theirs onto ours.
///
/// Twelve seeds run in the everyday suite, in about a second. For a wider sweep set
/// `WOODCASE_FUZZ_SEEDS` to a seed count; the extended case runs every check on seeds
/// 10001 onward (10,000 seeds take about two and a half minutes on a loaded machine):
///
/// ```sh
/// WOODCASE_FUZZ_SEEDS=1000 swift test --filter DocumentMergeFuzzTests
/// ```
///
/// A failing seed is reproduced by adding it to ``seeds``, and earns a cut-down case in
/// `DocumentMergeFuzzRegressionTests`.
@MainActor
struct DocumentMergeFuzzTests {
    /// The everyday seeds. Odd ones give both sides one label, so both mint the same ids.
    nonisolated static let seeds: [UInt64] = [1, 2, 3, 5, 8, 13, 42, 99, 777, 2026, 31337, 8_675_309]

    /// How many operations each side draws.
    nonisolated static let operationsPerSide = 50

    /// The extended sweep's seeds, from `WOODCASE_FUZZ_SEEDS`; none when it is unset.
    nonisolated static let extendedSeeds: [UInt64] = {
        guard let text = ProcessInfo.processInfo.environment["WOODCASE_FUZZ_SEEDS"], let count = Int(text), count > 0 else { return [] }
        return (1 ... count).map { UInt64(10000 + $0) }
    }()

    // MARK: - Helpers

    /// A fresh copy of a document, so editing it leaves the original alone.
    private static func copy(_ document: EditableDocument) -> EditableDocument {
        EditableDocument(from: document.materialize())
    }

    /// A document as its file writes it. Compared this way rather than as values: an
    /// edit made live can hold `.double(0)` where the codec, and any file, gives `.int(0)`.
    private static func written(_ document: EditableDocument) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(document.materialize())
    }

    /// Draws `operationsPerSide` merge-set operations into `document`, applying each one
    /// that applies, and returns those.
    @discardableResult
    private static func edit(
        _ document: EditableDocument, with generator: inout RandomEditGenerator, label: String, scope: String? = nil
    ) -> [EditOperation] {
        var applied: [EditOperation] = []
        for index in 0 ..< operationsPerSide {
            guard let operation = generator.mergeOperation(for: document, label: label, index: index, scope: scope) else { continue }
            if (try? document.apply(operation)) != nil {
                applied.append(operation)
            }
        }
        return applied
    }

    /// Applies `operations` in order to a copy of `document`, recording the first refusal.
    private static func applying(_ operations: [EditOperation], to document: EditableDocument, seed: UInt64) -> EditableDocument? {
        let result = copy(document)
        for (index, operation) in operations.enumerated() {
            do {
                try result.apply(operation)
            } catch {
                Issue.record("seed \(seed): operation \(index) of \(operations.count) refused — \(error)\n\(operation)")
                return nil
            }
        }
        return result
    }

    /// Edits both sides of one seed, merges, and checks everything a merge promises.
    private static func checkMerge(seed: UInt64) throws {
        let base = try FuzzFixture.mergeDocument()
        var generator = RandomEditGenerator(seed: seed)
        let labels = seed % 2 == 1 ? ("X", "X") : ("O", "T")
        let ours = copy(base)
        edit(ours, with: &generator, label: labels.0)
        let theirs = copy(base)
        edit(theirs, with: &generator, label: labels.1)

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        guard let merged = applying(result.operations, to: ours, seed: seed) else { return }

        let violations = MergeOracle(base: base, ours: ours, theirs: theirs, merged: merged, result: result).violations()
        #expect(violations.isEmpty, "seed \(seed):\n\(violations.joined(separator: "\n"))")
        #expect(result.keepsLocalChanges == (Self.written(merged) != Self.written(theirs)), "seed \(seed)")

        let again = DocumentMerge.merge(base: base, ours: merged, theirs: theirs)
        #expect(again.operations.isEmpty, "seed \(seed): a second merge emitted \(again.operations)")
    }

    // MARK: - The oracle

    @Test("Seeded merges apply without a refusal and satisfy the per-key oracle", arguments: seeds)
    func seededMerge(seed: UInt64) throws {
        try Self.checkMerge(seed: seed)
    }

    @Test(
        "Extended sweep: WOODCASE_FUZZ_SEEDS seeds through every check above",
        .enabled(if: !extendedSeeds.isEmpty, "Set WOODCASE_FUZZ_SEEDS to run the extended sweep."),
        arguments: extendedSeeds
    )
    func extendedMerge(seed: UInt64) throws {
        try Self.checkMerge(seed: seed)
        try Self.checkOursUnchanged(seed: seed)
        try Self.checkTheirsUnchanged(seed: seed)
        try Self.checkDisjointSubtrees(seed: seed)
    }

    @Test("The oracle flags a merge that ignores theirs' edits", arguments: seeds)
    func oracleRejectsIgnoringTheirs(seed: UInt64) throws {
        let base = try FuzzFixture.mergeDocument()
        var generator = RandomEditGenerator(seed: seed)
        let theirs = Self.copy(base)
        Self.edit(theirs, with: &generator, label: "T")
        let oracle = MergeOracle(base: base, ours: Self.copy(base), theirs: theirs, merged: Self.copy(base), result: MergeResult())
        #expect(!oracle.violations().isEmpty, "seed \(seed)")
    }

    // MARK: - One side unchanged

    @Test("When ours equals base the merge reproduces theirs exactly", arguments: seeds)
    func oursUnchanged(seed: UInt64) throws {
        try Self.checkOursUnchanged(seed: seed)
    }

    @Test("When theirs equals base the merge emits no operations", arguments: seeds)
    func theirsUnchanged(seed: UInt64) throws {
        try Self.checkTheirsUnchanged(seed: seed)
    }

    @Test("Edits in disjoint subtrees merge equal to replaying theirs' operations onto ours", arguments: seeds)
    func disjointSubtrees(seed: UInt64) throws {
        try Self.checkDisjointSubtrees(seed: seed)
    }

    // MARK: - Checks

    /// Ours unchanged: the merge reproduces theirs exactly, with nothing to report.
    private static func checkOursUnchanged(seed: UInt64) throws {
        let base = try FuzzFixture.mergeDocument()
        var generator = RandomEditGenerator(seed: seed)
        let theirs = Self.copy(base)
        Self.edit(theirs, with: &generator, label: "T")

        let result = DocumentMerge.merge(base: base, ours: Self.copy(base), theirs: theirs)
        #expect(result.conflicts.isEmpty, "seed \(seed): \(result.conflicts)")
        #expect(!result.keepsLocalChanges, "seed \(seed)")
        let merged = try #require(Self.applying(result.operations, to: base, seed: seed))
        #expect(Self.written(merged) == Self.written(theirs), "seed \(seed)")
    }

    /// Theirs unchanged: the merge emits nothing.
    private static func checkTheirsUnchanged(seed: UInt64) throws {
        let base = try FuzzFixture.mergeDocument()
        var generator = RandomEditGenerator(seed: seed)
        let ours = Self.copy(base)
        Self.edit(ours, with: &generator, label: "O")

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: Self.copy(base))
        #expect(result.operations.isEmpty, "seed \(seed): \(result.operations)")
        #expect(result.conflicts.isEmpty, "seed \(seed): \(result.conflicts)")
        #expect(result.keepsLocalChanges == (Self.written(ours) != Self.written(base)), "seed \(seed)")
    }

    /// Disjoint subtrees: merging equals replaying theirs' operations onto ours.
    private static func checkDisjointSubtrees(seed: UInt64) throws {
        let base = try FuzzFixture.mergeDocument()
        var generator = RandomEditGenerator(seed: seed)
        let ours = Self.copy(base)
        Self.edit(ours, with: &generator, label: "O", scope: FuzzFixture.disjointScopes[0])
        let theirs = Self.copy(base)
        let theirsOperations = Self.edit(theirs, with: &generator, label: "T", scope: FuzzFixture.disjointScopes[1])

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        #expect(result.conflicts.isEmpty, "seed \(seed): \(result.conflicts)")
        let merged = try #require(Self.applying(result.operations, to: ours, seed: seed))
        let replayed = try #require(Self.applying(theirsOperations, to: ours, seed: seed))
        #expect(Self.written(merged) == Self.written(replayed), "seed \(seed)")
    }
}
