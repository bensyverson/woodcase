//
//  PropertyReadCostProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What property reads and schema lookups cost on big documents, printed as `PROBE`
/// lines: every path of every node of `woodcase-app.pen`, one board's width on the
/// 5,000-node synthetic document, and every schema row of every type.
///
/// A measurement, not a check — `PropertyReadCostTests` holds the line by counting. It
/// runs only when asked, in a release build, and its figures mean something only beside
/// `uptime`:
///
/// ```sh
/// WOODCASE_READ_COST_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter PropertyReadCostProbe
/// ```
struct PropertyReadCostProbe {
    /// Milliseconds in a duration.
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Times `body` `runs` times and prints the median and p90.
    private static func measure(_ label: String, runs: Int, _ body: () throws -> Void) rethrows {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< runs {
            try samples.append(clock.measure(body))
        }
        samples.sort()
        print(String(
            format: "PROBE %@ median %.4f ms p90 %.4f ms",
            label, ms(samples[runs / 2]), ms(samples[runs * 9 / 10])
        ))
    }

    /// Every node under `children`, depth first.
    private static func flatten(_ children: [PenNode]) -> [PenNode] {
        children.flatMap { [$0] + flatten($0.kind.inlineChildrenIfPresent ?? []) }
    }

    @Test(
        "Property read and schema lookup cost on big documents",
        .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_READ_COST_PROBE"] != nil)
    )
    func probe() throws {
        let app = try PenParser.parse(contentsOf: PerformanceFixture.largestBundled())
        let nodes = Self.flatten(app.children)
        let pairs = nodes.flatMap { node in NodePropertyCodec.paths(for: node).map { (node, $0) } }
        print("PROBE woodcase-app nodes \(nodes.count) reads \(pairs.count)")
        try Self.measure("woodcase-app every path of every node", runs: 5) {
            for (node, path) in pairs {
                _ = try NodePropertyCodec.value(at: path, of: node)
            }
        }

        let synthetic = SyntheticPenDocument.make(nodeCount: PerformanceFixture.syntheticNodeCount)
        let board = try #require(synthetic.children.first)
        print("PROBE synthetic board descendants \(Self.flatten([board]).count - 1)")
        try Self.measure("synthetic board kind.width", runs: 51) {
            _ = try NodePropertyCodec.value(at: "kind.width", of: board)
        }
        try Self.measure("synthetic board common.name", runs: 51) {
            _ = try NodePropertyCodec.value(at: "common.name", of: board)
        }

        let lookups = PenNode.NodeType.allCases.flatMap { type in PenSchema.fields(for: type).map { (type, $0.path) } }
        print("PROBE schema lookups \(lookups.count)")
        Self.measure("schema field every row of every type", runs: 21) {
            for (type, path) in lookups {
                _ = PenSchema.field(path, for: type)
            }
        }
    }
}
