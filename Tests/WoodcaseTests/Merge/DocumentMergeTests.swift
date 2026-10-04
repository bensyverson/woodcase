//
//  DocumentMergeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``DocumentMerge``: the merge's operations, applied in order to the local document,
/// produce the merged document — for a wholesale rewrite, beside a local edit, and
/// again on a second merge of the same file.
@MainActor
struct DocumentMergeTests {
    private typealias F = MergeFixture

    // MARK: - Helpers

    /// Parses a fixture from `Fixtures/`.
    private static func fixture(_ name: String) throws -> EditableDocument {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "pen", subdirectory: "Fixtures"))
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// A fresh copy of a document, so applying to it leaves the original alone.
    private static func copy(_ document: EditableDocument) -> EditableDocument {
        EditableDocument(from: document.materialize())
    }

    /// Applies `operations` in order to a copy of `document` and returns the copy.
    private static func applying(_ operations: [EditOperation], to document: EditableDocument) throws -> EditableDocument {
        let result = copy(document)
        for operation in operations {
            try result.apply(operation)
        }
        return result
    }

    // MARK: - The rewrite fixture

    @Test("Applying the ops for the rewrite fixture pair to base materializes equal to theirs")
    func rewriteMaterializesTheirs() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")

        let result = DocumentMerge.merge(base: base, ours: Self.copy(base), theirs: theirs)
        #expect(result.conflicts.isEmpty)
        #expect(!result.keepsLocalChanges)
        #expect(!result.operations.isEmpty)

        let merged = try Self.applying(result.operations, to: base)
        #expect(merged.materialize() == theirs.materialize())
    }

    @Test("diff(from:to:) is a merge with no local changes")
    func diffIsMergeOfBaseOntoItself() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")
        let operations = DocumentMerge.diff(from: base, to: theirs)
        #expect(operations == DocumentMerge.merge(base: base, ours: base, theirs: theirs).operations)
        #expect(try Self.applying(operations, to: base).materialize() == theirs.materialize())
    }

    @Test("The rewrite fixture reversed — theirs back to base — also materializes equal")
    func rewriteReversed() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")
        let operations = DocumentMerge.diff(from: theirs, to: base)
        #expect(try Self.applying(operations, to: theirs).materialize() == base.materialize())
    }

    // MARK: - With a local edit

    @Test("With a local edit in ours, the merged result keeps it and reports the same-key conflict")
    func localEditKeptAndReported() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")
        let ours = Self.copy(base)
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "Page", properties: ["common.name": "Ben's page"])))
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "Title", properties: ["kind.content": "Hi"])))

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)

        #expect(result.conflicts.contains(MergeConflict(
            subject: .property(nodeID: "Page", path: "common.name"), kind: .bothChanged,
            base: "Page", ours: "Ben's page", theirs: "Main page"
        )))
        #expect(result.conflicts.contains { $0.subject == .existence(nodeID: "Title") && $0.kind == .editedLocallyDeletedExternally })
        #expect(result.keepsLocalChanges)

        let merged = try Self.applying(result.operations, to: ours)
        #expect(merged.nodes["Page"]?.common.name == "Ben's page")
        #expect(merged.nodes["Page"]?.extras["futureKey"] == true)
        #expect(merged.nodes["Title"].map { NodePropertyCodec.encodeOrNull("kind.content", of: $0) } == "Hi")
        #expect(merged.parents["Title"] == "Header")
        #expect(merged.parents["Logo"] == "Footer")
        #expect(merged.variables?["radius.s"] != nil)
    }

    @Test("When ours equals theirs there is nothing to apply and nothing kept")
    func oursEqualsTheirs() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")
        let result = DocumentMerge.merge(base: base, ours: Self.copy(theirs), theirs: theirs)
        #expect(result.operations.isEmpty)
        #expect(result.conflicts.isEmpty)
        #expect(!result.keepsLocalChanges)
    }

    // MARK: - Re-merging

    @Test("Re-merging theirs into the result yields no ops")
    func remergeIsEmpty() throws {
        let base = try Self.fixture("merge-rewrite-base")
        let theirs = try Self.fixture("merge-rewrite-theirs")
        let ours = Self.copy(base)
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "Page", properties: ["common.name": "Ben's page"])))
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "Title", properties: ["kind.content": "Hi"])))

        let first = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        let merged = try Self.applying(first.operations, to: ours)

        let again = DocumentMerge.merge(base: base, ours: merged, theirs: theirs)
        #expect(again.operations.isEmpty)
        #expect(again.keepsLocalChanges)

        let advanced = DocumentMerge.merge(base: theirs, ours: merged, theirs: theirs)
        #expect(advanced.operations.isEmpty)
        #expect(advanced.conflicts.isEmpty)
    }

    // MARK: - Every fixture

    @Test("A diff from an empty document to any fixture rebuilds it")
    func diffFromEmptyRebuildsEveryFixture() throws {
        let urls = try #require(Bundle.module.urls(forResourcesWithExtension: "pen", subdirectory: "Fixtures"))
        #expect(urls.count > 100)
        for url in urls {
            guard let target = try? EditableDocument(from: PenParser.parse(contentsOf: url)) else { continue }
            let empty = try F.document("")
            let operations = DocumentMerge.diff(from: empty, to: target)
            do {
                let rebuilt = try Self.applying(operations, to: empty)
                #expect(rebuilt.materialize() == target.materialize(), "\(url.lastPathComponent)")
            } catch {
                Issue.record("\(url.lastPathComponent): \(error)")
            }
        }
    }

    @Test("A diff between two unrelated fixtures turns one into the other")
    func diffBetweenFixtures() throws {
        let names = ["batch", "banking", "kit.lib", "every-node-type", "merge-rewrite-base", "preserved-extras"]
        let documents = try names.map(Self.fixture)
        for (i, from) in documents.enumerated() {
            for (j, to) in documents.enumerated() where i != j {
                do {
                    let operations = DocumentMerge.diff(from: from, to: to)
                    #expect(try Self.applying(operations, to: from).materialize() == to.materialize(), "\(names[i]) → \(names[j])")
                } catch {
                    Issue.record("\(names[i]) → \(names[j]): \(error)")
                }
            }
        }
    }
}

private extension NodePropertyCodec {
    /// A property's value, or ``AnyCodable/null`` when it cannot be read.
    static func encodeOrNull(_ path: String, of node: PenNode) -> AnyCodable {
        (try? value(at: path, of: node)) ?? .null
    }
}
