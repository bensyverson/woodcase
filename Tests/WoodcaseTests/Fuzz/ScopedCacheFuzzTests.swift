//
//  ScopedCacheFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// After any edit, the scoped caches agree with a document built from scratch.
///
/// Each step warms every cache the edit could falsify — every revision, every instance's
/// expansion, the component loops — draws a random edit from the merge vocabulary (which
/// places instances, makes components, retypes, overrides and moves them) and compares
/// all three with a fresh document of the same content. Edits the document refuses are
/// skipped; the caches must survive a refusal too, so they are compared after it as well.
@MainActor
struct ScopedCacheFuzzTests {
    /// Every node's revision, filling the cache.
    @discardableResult
    private func revisions(of document: EditableDocument) -> [String: String] {
        document.nodes.keys.reduce(into: [:]) { $0[$1] = document.revision(of: $1) }
    }

    /// Every instance's expansion, filling the cache.
    @discardableResult
    private func expansions(of document: EditableDocument) -> [String: ExpandedRef] {
        document.nodes.reduce(into: [:]) { result, entry in
            if case .ref = entry.value.kind { result[entry.key] = try? document.expandRef(nodeID: entry.key) }
        }
    }

    @Test("scoped caches agree with a from-scratch document after random edits", arguments: [3, 17, 404, 2718, 31337, 65537] as [UInt64])
    func agreesWithScratch(seed: UInt64) throws {
        var generator = RandomEditGenerator(seed: seed)
        let document = try FuzzFixture.mergeDocument()
        for step in 0 ..< 120 {
            revisions(of: document)
            expansions(of: document)
            _ = document.componentLoopIndex
            guard let operation = generator.mergeOperation(for: document, label: "F", index: step) else { continue }
            try? document.apply(operation)

            let scratch = EditableDocument(from: document.materialize())
            #expect(revisions(of: document) == revisions(of: scratch), "seed \(seed) step \(step): a revision is stale after \(operation)")
            #expect(expansions(of: document) == expansions(of: scratch), "seed \(seed) step \(step): an expansion is stale after \(operation)")
            #expect(document.componentLoopIndex == scratch.componentLoopIndex, "seed \(seed) step \(step): the loops are stale after \(operation)")
        }
    }
}
