//
//  ComponentLoopFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Documents that arrive with component loops stay fast to edit.
///
/// Generated edits can no longer make a loop — the operations refuse — so these
/// documents are drawn with the guard off, as a file written elsewhere arrives. Merge
/// fuzz seeds 12456 and 13964 drew such documents before the guard existed, and their
/// detaches and overrides expanded 12 million and 80 thousand nodes; under the loop rule
/// every instance expands its loop at most once. Each operation is bounded at "not hung"
/// scale, because the parallel suite stretches wall time
/// (`project/gotchas.md`); the unloaded figures are in leaf `xaAJeF`'s report.
@MainActor
struct ComponentLoopFuzzTests {
    /// The merge-fuzz seeds that hung, and the operations each side draws.
    nonisolated static let seeds: [UInt64] = [12456, 13964]

    /// What an operation may take before the test calls it hung.
    private static let hung: Duration = .seconds(20)

    /// The documents a merge-fuzz seed draws with the loop guard off, the way the seeds
    /// drew them before it: each side unscoped and in its disjoint subtree, and theirs'
    /// edits replayed onto ours. Returns those holding a loop, and the slowest edit.
    static func loopyDocuments(seed: UInt64) throws -> ([EditableDocument], Duration) {
        let base = try FuzzFixture.mergeDocument()
        let clock = ContinuousClock()
        var slowest: Duration = .zero
        var documents: [EditableDocument] = []
        for scopes in [[String?](repeating: nil, count: 2), FuzzFixture.disjointScopes.map(Optional.some)] {
            var generator = RandomEditGenerator(seed: seed)
            let ours = EditableDocument(from: base.materialize())
            let theirs = EditableDocument(from: base.materialize())
            var theirsOperations: [EditOperation] = []
            for (side, label, scope) in [(ours, "O", scopes[0]), (theirs, "T", scopes[1])] {
                side.allowingComponentLoops {
                    for index in 0 ..< DocumentMergeFuzzTests.operationsPerSide {
                        guard let operation = generator.mergeOperation(for: side, label: label, index: index, scope: scope)
                        else { continue }
                        var applied = false
                        slowest = max(slowest, clock.measure { applied = (try? side.apply(operation)) != nil })
                        if applied, label == "T" { theirsOperations.append(operation) }
                    }
                }
            }
            let replayed = EditableDocument(from: ours.materialize())
            replayed.allowingComponentLoops {
                for operation in theirsOperations {
                    slowest = max(slowest, clock.measure { _ = try? replayed.apply(operation) })
                }
            }
            documents += [ours, theirs, replayed].filter { !$0.componentLoops.isEmpty }
        }
        return (documents, slowest)
    }

    /// Detaches every instance, each on a fresh copy, and overrides one key of each;
    /// returns the slowest.
    static func slowestDetachAndOverride(in document: EditableDocument) -> Duration {
        let clock = ContinuousClock()
        var slowest: Duration = .zero
        let refs = document.allNodeIDs.sorted().filter { id in
            if case .ref? = document.nodes[id]?.kind { true } else { false }
        }
        for ref in refs {
            let copy = EditableDocument(from: document.materialize())
            slowest = max(slowest, clock.measure {
                _ = try? copy.apply(.detachRef(EditOperation.DetachRef(refNodeID: ref)))
            })
            let other = EditableDocument(from: document.materialize())
            slowest = max(slowest, clock.measure {
                guard let key = other.overridableDescendantKeys(ofInstance: ref).dropFirst().first else { return }
                _ = try? other.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: ref, descendantID: key, properties: ["opacity": .double(0.5)]
                )))
            })
        }
        return slowest
    }

    @Test("Documents drawn with loops by the seeds that hung edit, detach and override promptly", arguments: seeds)
    func loopyFuzzDocumentsStayFast(seed: UInt64) throws {
        let (documents, slowestEdit) = try Self.loopyDocuments(seed: seed)
        #expect(!documents.isEmpty, "seed \(seed) drew no loop, so it tests nothing")
        #expect(slowestEdit < Self.hung, "seed \(seed): an edit took \(slowestEdit)")
        for document in documents {
            let slowest = Self.slowestDetachAndOverride(in: document)
            #expect(slowest < Self.hung, "seed \(seed): a detach or override took \(slowest)")
        }
    }

    @Test("A loop of tangled components detaches and overrides every instance promptly")
    func tangledLoopStaysFast() {
        let document = EditableDocument(from: ComponentLoopReadTests.chain(223))
        #expect(document.componentLoops.count == 1)
        #expect(Self.slowestDetachAndOverride(in: document) < Self.hung)
    }
}
