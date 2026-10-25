//
//  SessionShuffledDeliveryFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The relay contract (Penumbra leaf 596DJZ): two in-process collaborative sessions edit
/// at random over several rounds and exchange what they broadcast through a network that
/// delivers late, out of order and more than once — and they converge.
///
/// Each round every session makes a few random edits — on a document that already holds
/// some of the other's work, so its operations depend on the other session's — and a
/// random part of what is in flight is delivered, shuffled, some of it twice. Whatever is
/// left is delivered the same way at the end.
///
/// With undo in the mix, a session also undoes and redoes its own edits as it goes: an
/// undone delete creates the node again under its id while the other session may still
/// be writing to it, which is what a node's existence register must settle.
@MainActor
struct SessionShuffledDeliveryFuzzTests {
    /// One operation in flight to one session.
    private struct Delivery {
        var operation: CRDTOperation
        var from: Author
    }

    /// What one run exercised, so a suite of runs can show it reached the cases it is for.
    private struct Coverage {
        /// Undos that put back a node a delete removed.
        var undoneDeletes = 0
        /// Deliveries after which a replica was keeping a write for a deleted node.
        var keptWrites = 0
    }

    private let authors = [
        Author(name: "ana", peerID: PeerID(rawValue: "contract_A")),
        Author(name: "bo", peerID: PeerID(rawValue: "contract_B")),
    ]

    private func expectConverged(_ a: EditableDocument, _ b: EditableDocument, seed: UInt64) {
        let comment: Comment = "seed \(seed)"
        #expect(a.materialize() == b.materialize(), comment)
        #expect(a.rootOrder == b.rootOrder, comment)
        #expect(a.parents == b.parents, comment)
        #expect(a.children == b.children, comment)
        #expect(a.nodes == b.nodes, comment)
        #expect(a.fonts == b.fonts, comment)
        #expect(a.version == b.version, comment)
        #expect(a.fileToken == b.fileToken, comment)
        #expect(a.extras == b.extras, comment)
    }

    /// Runs one seed and returns what it exercised.
    ///
    /// - Parameters:
    ///   - seed: The random seed.
    ///   - rounds: Rounds of edits and partial delivery.
    ///   - editsPerRound: Edits each session makes per round.
    ///   - undoOneIn: When set, about one edit in this many is an undo, and as many again
    ///     a redo; `nil` for no undo.
    @discardableResult
    private func run(seed: UInt64, rounds: Int = 6, editsPerRound: Int = 8, undoOneIn: Int? = nil) throws -> Coverage {
        var coverage = Coverage()
        var generator = RandomEditGenerator(seed: seed)
        let base = FuzzFixture.document()
        let sessions = authors.map { DocumentSession(document: base, author: $0, file: nil, collaborative: true) }
        var inFlight: [[Delivery]] = Array(repeating: [], count: sessions.count)

        func deliver(_ count: Int, to index: Int) throws {
            inFlight[index].shuffle(using: &generator.rng)
            var batch = Array(inFlight[index].prefix(count))
            inFlight[index].removeFirst(min(count, inFlight[index].count))
            // Some arrive twice: a relay retry, a replay after reconnecting.
            batch += batch.filter { _ in Int.random(in: 0 ..< 4, using: &generator.rng) == 0 }
            batch.shuffle(using: &generator.rng)
            while !batch.isEmpty {
                let size = Int.random(in: 1 ... max(1, batch.count), using: &generator.rng)
                let chunk = batch.prefix(size)
                batch.removeFirst(chunk.count)
                let change = try sessions[index].submit(.remote(chunk.map(\.operation), from: chunk[chunk.startIndex].from))
                #expect(change.rejected.isEmpty, "seed \(seed)")
                if sessions[index].document.crdtDocument?.dormantWrites.isEmpty == false {
                    coverage.keptWrites += 1
                }
            }
        }

        /// A random edit for a session: an undo or redo when the run mixes them in.
        func origin(for session: DocumentSession, label: String, index: Int) -> SessionOrigin? {
            if let undoOneIn {
                switch Int.random(in: 0 ..< undoOneIn, using: &generator.rng) {
                case 0: return .undo
                case 1: return .redo
                default: break
                }
            }
            let operation: EditOperation? = if Int.random(in: 0 ..< 8, using: &generator.rng) == 0 {
                generator.documentPropertyEdit(in: session.document, label: label, index: index)
            } else {
                generator.operation(for: session.document, label: label, index: index)
            }
            return operation.map { .local(LocalEdit(operations: [$0])) }
        }

        for round in 0 ..< rounds {
            for (index, session) in sessions.enumerated() {
                let label = "\(Character(UnicodeScalar(65 + index)!))\(round)"
                for edit in 0 ..< editsPerRound {
                    guard let origin = origin(for: session, label: label, index: edit),
                          let change = try? session.submit(origin) else { continue }
                    if case .undo = origin, change.applied.contains(where: { if case .insertNode = $0.forward { true } else { false } }) {
                        coverage.undoneDeletes += 1
                    }
                    for other in sessions.indices where other != index {
                        inFlight[other] += change.broadcast.map { Delivery(operation: $0, from: authors[index]) }
                    }
                }
            }
            for index in sessions.indices where !inFlight[index].isEmpty {
                try deliver(Int.random(in: 0 ... inFlight[index].count, using: &generator.rng), to: index)
            }
        }
        for index in sessions.indices {
            try deliver(inFlight[index].count, to: index)
        }

        for session in sessions {
            #expect(session.document.crdtDocument?.heldOperations.isEmpty == true, "seed \(seed)")
        }
        expectConverged(sessions[0].document, sessions[1].document, seed: seed)
        return coverage
    }

    @Test("two sessions converge when ops arrive shuffled and duplicated", arguments: [
        1, 7, 42, 99, 1337, 2026, 31337, 271_828, 314_159, 8_675_309,
    ] as [UInt64])
    func shuffledAndDuplicatedConverge(seed: UInt64) throws {
        try run(seed: seed)
    }

    @Test("longer runs converge", arguments: [5, 123_456] as [UInt64])
    func longerRunsConverge(seed: UInt64) throws {
        try run(seed: seed, rounds: 12, editsPerRound: 12)
    }

    /// Criterion eTh of leaf Re3ipI: undo of a delete converges on every peer, with
    /// concurrent writes, under shuffled and duplicated delivery.
    @Test("two sessions undoing and redoing converge, undone deletes and kept writes included")
    func undoAndRedoConverge() throws {
        var total = Coverage()
        for seed in [3, 11, 58, 404, 777, 2718, 16180, 65536, 99991, 1_234_567] as [UInt64] {
            let coverage = try run(seed: seed, rounds: 8, editsPerRound: 10, undoOneIn: 6)
            total.undoneDeletes += coverage.undoneDeletes
            total.keptWrites += coverage.keptWrites
        }
        // The cases the run is for were reached, not just survived.
        #expect(total.undoneDeletes > 0)
        #expect(total.keptWrites > 0)
    }
}
