//
//  PenLayoutInvalidationMergeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Invalidations merge field by field: a host merges the document's with a rawness
/// change (``PenLayoutOptions/invalidation(from:)``), and Penumbra merges those of the
/// pipeline runs a newer one superseded.
struct PenLayoutInvalidationMergeTests {
    @Test("union names everything either invalidation names")
    func union() {
        let merged = PenLayoutInvalidation(nodes: ["a"], subtrees: ["s"])
            .union(PenLayoutInvalidation(nodes: ["b"], roots: ["R"]))
        #expect(merged == PenLayoutInvalidation(nodes: ["a", "b"], subtrees: ["s"], roots: ["R"]))
        #expect(PenLayoutInvalidation().union(PenLayoutInvalidation(everything: true)).everything)
    }

    @Test("formUnion merges in place, as union does")
    func formUnion() {
        var merged = PenLayoutInvalidation(nodes: ["a"], roots: ["R"])
        merged.formUnion(PenLayoutInvalidation(nodes: ["b"], subtrees: ["s"]))
        #expect(merged == PenLayoutInvalidation(nodes: ["a", "b"], subtrees: ["s"], roots: ["R"]))
        #expect(!merged.everything)

        merged.formUnion(PenLayoutInvalidation(everything: true))
        #expect(merged.everything)
        merged.formUnion(PenLayoutInvalidation())
        #expect(merged.everything, "merging in less never clears everything")
    }
}
