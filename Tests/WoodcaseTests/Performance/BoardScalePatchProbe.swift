//
//  BoardScalePatchProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a whole-board scale's patch costs, printed as `PROBE` lines: Penumbra's perf
/// board (``PerfBoardFixture``) scaled by 1.5 about its top-left corner, every operation of
/// the plan patched onto the node it names (``EditableDocument/patchedNode(for:onto:)``),
/// and the same plan as a gesture preview (``EditableDocument/previewNodes(for:)``), which
/// is what Penumbra's `GesturePreview` runs on the main thread at every step of a scale.
///
/// A measurement, not a check — `NodePropertyBatchCostTests` holds the line by counting.
/// It runs only when asked, and its figures mean something only beside `uptime`:
///
/// ```sh
/// WOODCASE_BOARD_SCALE_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter BoardScalePatchProbe
/// ```
struct BoardScalePatchProbe {
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
            format: "PROBE %@ median %.3f ms p90 %.3f ms",
            label, ms(samples[runs / 2]), ms(samples[runs * 9 / 10])
        ))
    }

    @Test(
        "Whole-board scale patch cost on the perf board",
        .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_BOARD_SCALE_PROBE"] != nil)
    )
    func probe() throws {
        let document = try EditableDocument(from: PerfBoardFixture.document())
        let board = try #require(document.rootOrder.first)
        let layout = PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
        let capture = try ScaleCapture(nodeIDs: [board], in: document, layout: layout)
        let plan = try capture.plan(factor: 1.5, anchor: .topLeft, in: document)
        let patches: [EditOperation.SetProperties] = plan.operations.compactMap {
            if case let .setProperties(op) = $0 { op } else { nil }
        }
        let keys = patches.reduce(0) { $0 + $1.properties.count }
        print("PROBE perf board operations \(plan.operations.count) patches \(patches.count) keys \(keys)")
        let histogram = patches.flatMap(\.properties.keys).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        print("PROBE perf board keys \(histogram.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" })")

        try Self.measure("perf board scale patchedNode", runs: 41) {
            for op in patches {
                _ = try document.patchedNode(for: op)
            }
        }
        try Self.measure("perf board scale per-key setting", runs: 41) {
            for op in patches {
                var node = try #require(document.node(id: op.nodeID))
                for (path, value) in op.properties {
                    node = try NodePropertyCodec.setting(value, at: path, on: node)
                }
            }
        }
        try Self.measure("perf board scale previewNodes", runs: 41) {
            _ = try document.previewNodes(for: plan.operations)
        }
    }
}
