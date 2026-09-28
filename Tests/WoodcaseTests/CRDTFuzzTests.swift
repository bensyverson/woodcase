//
//  CRDTFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A seedable random number generator for reproducible fuzz tests.
///
/// Uses a simple xoshiro256** algorithm seeded from a UInt64.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: (UInt64, UInt64, UInt64, UInt64)

    init(seed: UInt64) {
        // SplitMix64 to expand one seed into four state words
        var s = seed
        func next() -> UInt64 {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        state = (next(), next(), next(), next())
    }

    mutating func next() -> UInt64 {
        let result = rotl(state.1 &* 5, 7) &* 9
        let t = state.1 << 17
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= t
        state.3 = rotl(state.3, 45)
        return result
    }

    private func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }
}

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

    /// Creates a base document with ~10 nodes plus reusable components and refs.
    private func makeBaseDocument() -> PenDocument {
        let r1 = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect1"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let r2 = PenNode(
            id: "r2",
            common: PenNodeCommon(name: "Rect2"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(80)))
        )
        let t1 = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Text1"),
            kind: .text(PenNode.TextData(width: .fixed(200)))
        )
        let t2 = PenNode(
            id: "t2",
            common: PenNodeCommon(name: "Text2"),
            kind: .text(PenNode.TextData(width: .fixed(150)))
        )
        let g1 = PenNode(
            id: "g1",
            common: PenNodeCommon(name: "Group1"),
            kind: .group(PenNode.GroupData(children: [r2, t2]))
        )
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame1", theme: ["mode": "dark"]),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [r1, t1, g1]))
        )
        let r3 = PenNode(
            id: "r3",
            common: PenNodeCommon(name: "Rect3"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(60)))
        )
        let e1 = PenNode(
            id: "e1",
            common: PenNodeCommon(name: "Ellipse1"),
            kind: .ellipse(PenNode.EllipseData(width: .fixed(50)))
        )
        let f2 = PenNode(
            id: "f2",
            common: PenNodeCommon(name: "Frame2", theme: ["density": "compact"]),
            kind: .frame(PenNode.FrameData(width: .fixed(300), children: [r3, e1]))
        )
        let r4 = PenNode(
            id: "r4",
            common: PenNodeCommon(name: "Rect4"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(120)))
        )

        // Reusable component: a button with a label and icon
        let btnLabel = PenNode(
            id: "btnL",
            common: PenNodeCommon(name: "BtnLabel"),
            kind: .text(PenNode.TextData(width: .fixed(80)))
        )
        let btnIcon = PenNode(
            id: "btnI",
            common: PenNodeCommon(name: "BtnIcon"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(24)))
        )
        let btnComp = PenNode(
            id: "btnC",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(width: .fixed(120), children: [btnIcon, btnLabel]))
        )

        // Ref instances of the button component
        let ref1 = PenNode(
            id: "bR1",
            common: PenNodeCommon(name: "Submit"),
            kind: .ref(PenNode.RefData(ref: "btnC"))
        )
        let ref2 = PenNode(
            id: "bR2",
            common: PenNodeCommon(name: "Cancel"),
            kind: .ref(PenNode.RefData(ref: "btnC", descendants: [
                "btnL": PenDescendantOverride(properties: ["name": .string("Cancel")]),
            ]))
        )

        return PenDocument(
            themes: ["mode": ["light", "dark"], "density": ["normal", "compact"]],
            variables: [
                "bgColor": PenVariable(type: .color, value: .themed([
                    PenThemedValue(value: .string("#FFFFFF"), theme: ["mode": "light"]),
                    PenThemedValue(value: .string("#000000"), theme: ["mode": "dark"]),
                ])),
                "spacing": PenVariable(type: .number, value: .themed([
                    PenThemedValue(value: .double(16), theme: ["density": "normal"]),
                    PenThemedValue(value: .double(8), theme: ["density": "compact"]),
                ])),
            ],
            children: [f1, f2, r4, btnComp, ref1, ref2]
        )
    }

    /// Generates a random `EditOperation` valid for the current document state.
    /// Returns `nil` if no valid operation could be generated.
    private func generateRandomOp(
        for doc: EditableDocument,
        rng: inout SeededRandomNumberGenerator,
        peerLabel: String,
        opIndex: Int
    ) -> EditOperation? {
        let nodeIDs = Array(doc.allNodeIDs).sorted()
        guard !nodeIDs.isEmpty else { return nil }

        // Weight structural ops (insert/delete/move) more heavily since they
        // exercise the most complex convergence paths.
        // 0-11: existing ops, 12-13: overrideDescendant, 14: detachRef
        let opType = Int.random(in: 0 ..< 15, using: &rng)

        switch opType {
        case 0:
            // Insert a leaf node (rectangle, text, or ellipse)
            let newID = "\(peerLabel)_ins_\(opIndex)"
            let parentCandidates = nodeIDs.filter { doc.nodes[$0]?.kind.canHaveChildren == true }
            let parentID: String? = if parentCandidates.isEmpty {
                nil
            } else if Bool.random(using: &rng) {
                parentCandidates.randomElement(using: &rng)
            } else {
                nil
            }
            let kindChoice = Int.random(in: 0 ..< 3, using: &rng)
            let node = switch kindChoice {
            case 0:
                PenNode(
                    id: newID,
                    common: PenNodeCommon(name: "Fuzz_\(newID)"),
                    kind: .rectangle(PenNode.RectangleData(width: .fixed(Double.random(in: 10 ... 200, using: &rng))))
                )
            case 1:
                PenNode(
                    id: newID,
                    common: PenNodeCommon(name: "Fuzz_\(newID)"),
                    kind: .text(PenNode.TextData(width: .fixed(Double.random(in: 50 ... 300, using: &rng))))
                )
            default:
                PenNode(
                    id: newID,
                    common: PenNodeCommon(name: "Fuzz_\(newID)"),
                    kind: .ellipse(PenNode.EllipseData(width: .fixed(Double.random(in: 20 ... 150, using: &rng))))
                )
            }
            // Sometimes specify an explicit index
            var index: Int?
            if Bool.random(using: &rng) {
                let count = parentID.flatMap { doc.children[$0]?.count } ?? doc.rootOrder.count
                index = count > 0 ? Int.random(in: 0 ... count, using: &rng) : 0
            }
            return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: index))

        case 1:
            // Insert a container (frame or group) with one child — exercises subtree insert
            let newID = "\(peerLabel)_ins_\(opIndex)"
            let childID = "\(peerLabel)_ins_\(opIndex)c"
            let parentCandidates = nodeIDs.filter { doc.nodes[$0]?.kind.canHaveChildren == true }
            let parentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
                nil
            } else {
                parentCandidates.randomElement(using: &rng)
            }
            let child = PenNode(
                id: childID,
                common: PenNodeCommon(name: "FuzzChild_\(childID)"),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(Double.random(in: 10 ... 100, using: &rng))))
            )
            let node = if Bool.random(using: &rng) {
                PenNode(
                    id: newID,
                    common: PenNodeCommon(name: "Fuzz_\(newID)"),
                    kind: .frame(PenNode.FrameData(width: .fixed(Double.random(in: 100 ... 500, using: &rng)), children: [child]))
                )
            } else {
                PenNode(
                    id: newID,
                    common: PenNodeCommon(name: "Fuzz_\(newID)"),
                    kind: .group(PenNode.GroupData(children: [child]))
                )
            }
            return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID))

        case 2, 3:
            // Delete a random node (weighted 2x)
            let nodeID = nodeIDs.randomElement(using: &rng)!
            return .deleteNode(EditOperation.DeleteNode(nodeID: nodeID))

        case 4, 5:
            // Move a random node (weighted 2x)
            let nodeID = nodeIDs.randomElement(using: &rng)!
            let parentCandidates = nodeIDs.filter {
                $0 != nodeID && doc.nodes[$0]?.kind.canHaveChildren == true
            }
            let newParentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
                nil
            } else {
                parentCandidates.randomElement(using: &rng)
            }
            // Sometimes specify an explicit index
            var index: Int?
            if Bool.random(using: &rng) {
                let count = newParentID.flatMap { doc.children[$0]?.count } ?? doc.rootOrder.count
                index = count > 0 ? Int.random(in: 0 ... count, using: &rng) : 0
            }
            return .moveNode(EditOperation.MoveNode(nodeID: nodeID, newParentID: newParentID, index: index))

        case 6:
            // Update common properties
            let nodeID = nodeIDs.randomElement(using: &rng)!
            guard let node = doc.nodes[nodeID] else { return nil }
            var common = node.common
            let propsToChange = Int.random(in: 1 ... 3, using: &rng)
            for _ in 0 ..< propsToChange {
                let propChoice = Int.random(in: 0 ..< 6, using: &rng)
                switch propChoice {
                case 0: common.name = "Fuzz_\(peerLabel)_\(opIndex)"
                case 1: common.opacity = .literal(Double.random(in: 0 ... 1, using: &rng))
                case 2: common.x = .literal(Double.random(in: -500 ... 500, using: &rng))
                case 3: common.y = .literal(Double.random(in: -500 ... 500, using: &rng))
                case 4:
                    // Set a theme override on this node (exercises inherited theme resolution)
                    let axes = Array(doc.themes?.keys ?? [:].keys)
                    if let axis = axes.randomElement(using: &rng),
                       let options = doc.themes?[axis],
                       let option = options.randomElement(using: &rng)
                    {
                        var theme = common.theme ?? [:]
                        theme[axis] = option
                        common.theme = theme
                    }
                case 5:
                    // Clear theme override (revert to inherited)
                    common.theme = nil
                default: break
                }
            }
            return .updateCommon(EditOperation.UpdateCommon(nodeID: nodeID, common: common))

        case 7:
            // Add/update/remove a variable
            let varName = "fuzzVar\(Int.random(in: 0 ..< 5, using: &rng))"
            if let existing = doc.variables?[varName] {
                // 50% update, 50% remove
                if Bool.random(using: &rng) {
                    let variable = PenVariable(
                        type: existing.type,
                        value: .simple(AnyCodable(stringLiteral: "#\(String(format: "%06X", Int.random(in: 0 ..< 0xFFFFFF, using: &rng)))"))
                    )
                    return .updateVariable(EditOperation.UpdateVariable(name: varName, variable: variable))
                } else {
                    return .removeVariable(EditOperation.RemoveVariable(name: varName))
                }
            } else {
                let variable = PenVariable(
                    type: .color,
                    value: .simple(AnyCodable(stringLiteral: "#\(String(format: "%06X", Int.random(in: 0 ..< 0xFFFFFF, using: &rng)))"))
                )
                return .addVariable(EditOperation.AddVariable(name: varName, variable: variable))
            }

        case 8:
            // Add/update/remove a theme axis
            let axisName = "fuzzAxis\(Int.random(in: 0 ..< 3, using: &rng))"
            let options = ["optA", "optB", "optC"].prefix(Int.random(in: 2 ... 3, using: &rng))
            if doc.themes?[axisName] != nil {
                if Bool.random(using: &rng) {
                    return .updateThemeAxis(EditOperation.UpdateThemeAxis(name: axisName, options: Array(options)))
                } else {
                    return .removeThemeAxis(EditOperation.RemoveThemeAxis(name: axisName))
                }
            } else {
                return .addThemeAxis(EditOperation.AddThemeAxis(name: axisName, options: Array(options)))
            }

        case 9:
            // Add/update/remove an import
            let alias = "fuzzImport\(Int.random(in: 0 ..< 4, using: &rng))"
            let path = "./fuzz\(Int.random(in: 0 ..< 10, using: &rng)).pen"
            if doc.imports?[alias] != nil {
                if Bool.random(using: &rng) {
                    return .updateImport(EditOperation.UpdateImport(alias: alias, path: path))
                } else {
                    return .removeImport(EditOperation.RemoveImport(alias: alias))
                }
            } else {
                return .addImport(EditOperation.AddImport(alias: alias, path: path))
            }

        case 10, 11:
            // Deliberately target a "hot" node — one of the initial container nodes
            // that multiple peers are likely to contend over.
            let hotNodes = ["f1", "f2", "g1"]
            let hotID = hotNodes.randomElement(using: &rng)!
            guard doc.nodes[hotID] != nil else { return nil }
            let action = Int.random(in: 0 ..< 3, using: &rng)
            switch action {
            case 0:
                // Move hot node
                let parentCandidates = nodeIDs.filter {
                    $0 != hotID && doc.nodes[$0]?.kind.canHaveChildren == true
                }
                let newParentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
                    nil
                } else {
                    parentCandidates.randomElement(using: &rng)
                }
                return .moveNode(EditOperation.MoveNode(nodeID: hotID, newParentID: newParentID))
            case 1:
                // Delete hot node
                return .deleteNode(EditOperation.DeleteNode(nodeID: hotID))
            default:
                // Update hot node properties
                guard let node = doc.nodes[hotID] else { return nil }
                var common = node.common
                common.name = "Hot_\(peerLabel)_\(opIndex)"
                common.opacity = .literal(Double.random(in: 0 ... 1, using: &rng))
                return .updateCommon(EditOperation.UpdateCommon(nodeID: hotID, common: common))
            }

        case 12, 13:
            // Override a descendant on a ref node (weighted 2x for LWW coverage)
            let refNodes = nodeIDs.filter { id in
                if case .ref = doc.nodes[id]?.kind { return true }
                return false
            }
            guard let refID = refNodes.randomElement(using: &rng) else { return nil }
            guard case let .ref(refData) = doc.nodes[refID]?.kind else { return nil }

            // Pick a descendant to override — either one of the component's known children
            // or a fixed set of known descendant IDs from the base document's component
            let descendantCandidates = Array(refData.descendants?.keys ?? [:].keys) + ["btnL", "btnI"]
            let descendantID = descendantCandidates.randomElement(using: &rng) ?? "btnL"

            // Generate random override properties — targeting name and opacity
            // to create high-contention LWW scenarios on the same ref
            var properties: [String: AnyCodable] = [:]
            let propChoice = Int.random(in: 0 ..< 3, using: &rng)
            switch propChoice {
            case 0:
                properties["name"] = .string("Fuzz_\(peerLabel)_\(opIndex)")
            case 1:
                properties["opacity"] = .double(Double.random(in: 0 ... 1, using: &rng))
            default:
                properties["name"] = .string("Fuzz_\(peerLabel)_\(opIndex)")
                properties["opacity"] = .double(Double.random(in: 0 ... 1, using: &rng))
            }

            return .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: refID,
                descendantID: descendantID,
                properties: properties
            ))

        case 14:
            // Detach a ref node — replacing it with expanded independent nodes
            let refNodes = nodeIDs.filter { id in
                if case .ref = doc.nodes[id]?.kind { return true }
                return false
            }
            guard let refID = refNodes.randomElement(using: &rng) else { return nil }
            return .detachRef(EditOperation.DetachRef(refNodeID: refID))

        default:
            return nil
        }
    }

    /// Runs a single fuzz scenario with the given seed.
    ///
    /// Creates 2–3 peers from the same base document. Each peer applies 50–100
    /// random local operations. All generated CRDT operations are then exchanged
    /// in a random order. Asserts all peers converge to identical state.
    private func runFuzzScenario(seed: UInt64, peerCount: Int, opCount: Int) throws {
        var rng = SeededRandomNumberGenerator(seed: seed)

        let baseDoc = makeBaseDocument()
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
                guard let op = generateRandomOp(for: peer, rng: &rng, peerLabel: peerLabel, opIndex: opIdx) else {
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
            guard let chosenPeer = nonEmpty.randomElement(using: &rng) else { break }

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
