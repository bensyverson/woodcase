//
//  PropertyReadCostBench.swift
//  WoodcaseBench
//

import Foundation
import Woodcase
import WoodcasePerfFixtures

/// What property reads and schema lookups cost on big documents: every path of every
/// node of `woodcase-app.pen`, one board's width on the 5,000-node synthetic document,
/// and every schema row of every type.
///
/// `PropertyReadCostTests` holds the line by counting.
enum PropertyReadCostBench {
    /// The bench.
    static let bench = Bench(
        name: "property-read-cost",
        summary: "Property reads and schema lookups on woodcase-app.pen and the 5,000-node synthetic document",
        run: { _ in try run() }
    )

    private static func run() throws {
        let app = try PenParser.parse(contentsOf: PerfFixtureFile.woodcaseApp.url)
        let nodes = PenNode.flatten(app.children)
        let pairs = nodes.flatMap { node in NodePropertyCodec.paths(for: node).map { (node, $0) } }
        print("PROBE woodcase-app nodes \(nodes.count) reads \(pairs.count)")
        try BenchClock.measure("woodcase-app every path of every node", runs: 5) {
            for (node, path) in pairs {
                _ = try NodePropertyCodec.value(at: path, of: node)
            }
        }

        let synthetic = SyntheticPenDocument.make(nodeCount: SyntheticPenDocument.budgetNodeCount)
        guard let board = synthetic.children.first else { return }
        print("PROBE synthetic board descendants \(PenNode.flatten([board]).count - 1)")
        try BenchClock.measure("synthetic board kind.width", runs: 51) {
            _ = try NodePropertyCodec.value(at: "kind.width", of: board)
        }
        try BenchClock.measure("synthetic board common.name", runs: 51) {
            _ = try NodePropertyCodec.value(at: "common.name", of: board)
        }

        let lookups = PenNode.NodeType.allCases.flatMap { type in PenSchema.fields(for: type).map { (type, $0.path) } }
        print("PROBE schema lookups \(lookups.count)")
        BenchClock.measure("schema field every row of every type", runs: 21) {
            for (type, path) in lookups {
                _ = PenSchema.field(path, for: type)
            }
        }
    }
}
