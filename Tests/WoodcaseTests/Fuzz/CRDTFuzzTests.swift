//
//  CRDTFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTFuzzTests {
    // MARK: - Helpers

    private func assertConverged(_ a: EditableDocument, _ b: EditableDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.rootOrder == b.rootOrder, "rootOrder diverged", sourceLocation: sourceLocation)
        #expect(a.nodes.keys.sorted() == b.nodes.keys.sorted(), "node keys diverged", sourceLocation: sourceLocation)
        for key in a.nodes.keys {
            #expect(a.nodes[key] == b.nodes[key], "node \(key) diverged", sourceLocation: sourceLocation)
        }
        #expect(a.children == b.children, "children diverged", sourceLocation: sourceLocation)
        #expect(a.parents == b.parents, "parents diverged", sourceLocation: sourceLocation)
        #expect(a.variables == b.variables, "variables diverged", sourceLocation: sourceLocation)
        #expect(a.imports == b.imports, "imports diverged", sourceLocation: sourceLocation)
        #expect(a.themes == b.themes, "themes diverged", sourceLocation: sourceLocation)
    }

    /// Runs a single fuzz scenario with the given seed.
    ///
    /// Creates 2–3 peers from the same base document. Each peer applies 50–100
    /// random local operations. All generated CRDT operations are then exchanged
    /// in a random order. Asserts all peers converge to identical state.
    private func runFuzzScenario(seed: UInt64, peerCount: Int, opCount: Int) throws {
        var generator = RandomEditGenerator(seed: seed)

        let baseDoc = FuzzFixture.document()
        let peerIDs = (0 ..< peerCount).map { i in
            PeerID(rawValue: "fuzz_peer_\(Character(UnicodeScalar(65 + i)!))")
        }

        let peers = peerIDs.map { EditableDocument(from: baseDoc, peerID: $0) }
        // Per-peer operation queues (preserving causal order within each peer)
        var peerOps: [[([CRDTOperation], Int)]] = Array(repeating: [], count: peerCount)

        // Each peer generates random local operations
        for (peerIdx, peer) in peers.enumerated() {
            let peerLabel = String(Character(UnicodeScalar(65 + peerIdx)!))
            for opIdx in 0 ..< opCount {
                guard let op = generator.operation(for: peer, label: peerLabel, index: opIdx) else {
                    continue
                }
                do {
                    let crdtOps = try peer.applyLocal(op)
                    if !crdtOps.isEmpty {
                        peerOps[peerIdx].append((crdtOps, peerIdx))
                    }
                } catch {
                    // Invalid operation for current state (e.g., cycle, node not found).
                    // Skip and continue — this is expected in fuzz testing.
                    continue
                }
            }
        }

        // Randomly interleave across peers while preserving per-peer causal order.
        // Pop from the front of a randomly chosen non-empty queue until all are drained.
        var cursors = Array(repeating: 0, count: peerCount)
        let totalBatches = peerOps.reduce(0) { $0 + $1.count }

        for _ in 0 ..< totalBatches {
            // Pick a random non-empty peer queue
            let nonEmpty = (0 ..< peerCount).filter { cursors[$0] < peerOps[$0].count }
            guard let chosenPeer = nonEmpty.randomElement(using: &generator.rng) else { break }

            let (ops, originPeer) = peerOps[chosenPeer][cursors[chosenPeer]]
            cursors[chosenPeer] += 1

            // Apply to all other peers
            for (peerIdx, peer) in peers.enumerated() {
                if peerIdx != originPeer {
                    peer.applyRemote(ops)
                }
            }
        }

        // Assert all peers converged
        for i in 1 ..< peers.count {
            assertConverged(peers[0], peers[i])
        }

        // Verify the converged state produces a valid pipeline output.
        // This catches cases where peers converge to the same *broken* state
        // (e.g. themes that crash resolution, malformed nodes that break layout).
        let converged = peers[0]
        let materialized = converged.materialize()
        let expanded = PenRefExpander.expand(materialized)
        let resolved = PenVariableResolver.resolve(expanded)
        let rects = PenLayoutEngine.layout(resolved)

        // Every visible node in the resolved document should have a layout rect
        for node in resolved.children {
            #expect(rects[node.id] != nil, "Root node \(node.id) missing layout rect after convergence")
        }
    }

    // MARK: - Fuzz Tests

    @Test("Fuzz: 2 peers, 50 ops each, seed 1")
    func fuzz2Peers50Ops_seed1() throws {
        try runFuzzScenario(seed: 1, peerCount: 2, opCount: 50)
    }

    @Test("Fuzz: 2 peers, 50 ops each, seed 42")
    func fuzz2Peers50Ops_seed42() throws {
        try runFuzzScenario(seed: 42, peerCount: 2, opCount: 50)
    }

    @Test("Fuzz: 2 peers, 100 ops each, seed 1337")
    func fuzz2Peers100Ops_seed1337() throws {
        try runFuzzScenario(seed: 1337, peerCount: 2, opCount: 100)
    }

    @Test("Fuzz: 3 peers, 75 ops each, seed 9999")
    func fuzz3Peers75Ops_seed9999() throws {
        try runFuzzScenario(seed: 9999, peerCount: 3, opCount: 75)
    }

    @Test("Fuzz: 3 peers, 100 ops each, seed 2026")
    func fuzz3Peers100Ops_seed2026() throws {
        try runFuzzScenario(seed: 2026, peerCount: 3, opCount: 100)
    }

    @Test("Fuzz: 2 peers, 50 ops each, seed 777")
    func fuzz2Peers50Ops_seed777() throws {
        try runFuzzScenario(seed: 777, peerCount: 2, opCount: 50)
    }

    @Test("Fuzz: 3 peers, 50 ops each, seed 314159")
    func fuzz3Peers50Ops_seed314159() throws {
        try runFuzzScenario(seed: 314_159, peerCount: 3, opCount: 50)
    }

    // Additional seeds for broader coverage

    @Test("Fuzz: 2 peers, 100 ops each, seed 55555")
    func fuzz2Peers100Ops_seed55555() throws {
        try runFuzzScenario(seed: 55555, peerCount: 2, opCount: 100)
    }

    @Test("Fuzz: 3 peers, 100 ops each, seed 98765")
    func fuzz3Peers100Ops_seed98765() throws {
        try runFuzzScenario(seed: 98765, peerCount: 3, opCount: 100)
    }

    @Test("Fuzz: 2 peers, 200 ops each, seed 271828")
    func fuzz2Peers200Ops_seed271828() throws {
        try runFuzzScenario(seed: 271_828, peerCount: 2, opCount: 200)
    }

    @Test("Fuzz: 3 peers, 150 ops each, seed 161803")
    func fuzz3Peers150Ops_seed161803() throws {
        try runFuzzScenario(seed: 161_803, peerCount: 3, opCount: 150)
    }

    @Test("Fuzz: 2 peers, 75 ops each, seed 1000000007")
    func fuzz2Peers75Ops_seedPrime() throws {
        try runFuzzScenario(seed: 1_000_000_007, peerCount: 2, opCount: 75)
    }

    @Test("Fuzz: 3 peers, 75 ops each, seed 8675309")
    func fuzz3Peers75Ops_seed8675309() throws {
        try runFuzzScenario(seed: 8_675_309, peerCount: 3, opCount: 75)
    }

    @Test("Fuzz: 2 peers, 150 ops each, seed 31415926")
    func fuzz2Peers150Ops_seed31415926() throws {
        try runFuzzScenario(seed: 31_415_926, peerCount: 2, opCount: 150)
    }

    @Test("Fuzz: 3 peers, 200 ops each, seed 27182818")
    func fuzz3Peers200Ops_seed27182818() throws {
        try runFuzzScenario(seed: 27_182_818, peerCount: 3, opCount: 200)
    }
}
