//
//  PropertyWriteCostProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What property writes cost on big documents, before and after, printed as `PROBE`
/// lines: one board's width and name on the 5,000-node synthetic document, and every path
/// of every node of `woodcase-app.pen` written back with its own value. "Before" is
/// ``PropertyWriteOracleTests/Oracle``, the old whole-payload write kept as the oracle;
/// "after" is ``NodePropertyCodec/setting(_:at:on:)``.
///
/// A measurement, not a check — `PropertyWriteCostTests` holds the line by counting. It
/// runs only when asked, and its figures mean something only beside `uptime`:
///
/// ```sh
/// WOODCASE_WRITE_COST_PROBE=1 swift test --filter PropertyWriteCostProbe
/// WOODCASE_WRITE_COST_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter PropertyWriteCostProbe
/// ```
struct PropertyWriteCostProbe {
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

    /// One write, the old way or the new.
    private typealias Write = @Sendable (AnyCodable, String, PenNode) throws -> PenNode

    /// The two implementations, labeled.
    private static let writes: [(String, Write)] = [
        ("before", PropertyWriteOracleTests.Oracle.setting),
        ("after", NodePropertyCodec.setting),
    ]

    @Test(
        "Property write cost on big documents, before and after",
        .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_WRITE_COST_PROBE"] != nil)
    )
    func probe() throws {
        let synthetic = SyntheticPenDocument.make(nodeCount: PerformanceFixture.syntheticNodeCount)
        let board = try #require(synthetic.children.first)
        print("PROBE synthetic board descendants \(Self.flatten([board]).count - 1)")
        for (label, write) in Self.writes {
            try Self.measure("\(label) synthetic board kind.width", runs: 21) {
                _ = try write(.int(777), "kind.width", board)
            }
            try Self.measure("\(label) synthetic board common.name", runs: 21) {
                _ = try write(.string("Renamed"), "common.name", board)
            }
        }

        let app = try PenParser.parse(contentsOf: PerformanceFixture.largestBundled())
        let nodes = Self.flatten(app.children)
        let writes = try nodes.flatMap { node in
            try NodePropertyCodec.paths(for: node).map { try (node, $0, NodePropertyCodec.value(at: $0, of: node)) }
        }
        print("PROBE woodcase-app nodes \(nodes.count) writes \(writes.count)")
        for (label, write) in Self.writes {
            Self.measure("\(label) woodcase-app every path of every node", runs: 5) {
                for (node, path, value) in writes {
                    _ = try? write(value, path, node)
                }
            }
        }
    }
}
