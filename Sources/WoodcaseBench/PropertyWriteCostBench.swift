//
//  PropertyWriteCostBench.swift
//  WoodcaseBench
//

import Foundation
import Woodcase
import WoodcasePerfFixtures

/// What property writes cost on big documents: one board's width and name on the
/// 5,000-node synthetic document, and every path of every node of `woodcase-app.pen`
/// written back with its own value, through ``NodePropertyCodec/setting(_:at:on:)``.
///
/// `PropertyWriteCostTests` holds the line by counting. The old whole-payload write this
/// was once compared with stays in the suite as `PropertyWriteOracleTests.Oracle`; it is
/// a test oracle, not a library path, so the bench does not time it.
enum PropertyWriteCostBench {
    /// The bench.
    static let bench = Bench(
        name: "property-write-cost",
        summary: "Property writes on the 5,000-node synthetic document and every path of woodcase-app.pen",
        run: { _ in try run() }
    )

    private static func run() throws {
        let synthetic = SyntheticPenDocument.make(nodeCount: SyntheticPenDocument.budgetNodeCount)
        guard let board = synthetic.children.first else { return }
        print("PROBE synthetic board descendants \(PenNode.flatten([board]).count - 1)")
        try BenchClock.measure("synthetic board kind.width", runs: 21) {
            _ = try NodePropertyCodec.setting(.int(777), at: "kind.width", on: board)
        }
        try BenchClock.measure("synthetic board common.name", runs: 21) {
            _ = try NodePropertyCodec.setting(.string("Renamed"), at: "common.name", on: board)
        }

        let app = try PenParser.parse(contentsOf: PerfFixtureFile.woodcaseApp.url)
        let nodes = PenNode.flatten(app.children)
        let writes = try nodes.flatMap { node in
            try NodePropertyCodec.paths(for: node).map { try (node, $0, NodePropertyCodec.value(at: $0, of: node)) }
        }
        print("PROBE woodcase-app nodes \(nodes.count) writes \(writes.count)")
        BenchClock.measure("woodcase-app every path of every node", runs: 5) {
            for (node, path, value) in writes {
                _ = try? NodePropertyCodec.setting(value, at: path, on: node)
            }
        }
    }
}
