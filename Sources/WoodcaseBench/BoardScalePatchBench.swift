//
//  BoardScalePatchBench.swift
//  WoodcaseBench
//

import Foundation
import Woodcase
import WoodcasePerfFixtures

/// What a whole-board scale's patch costs: Penumbra's perf board (``PerfBoardFixture``)
/// scaled by 1.5 about its top-left corner, every key of the plan written one at a time
/// onto the node it names, and the same plan as a gesture preview
/// (``EditableDocument/previewNodes(for:)``), which is what Penumbra's `GesturePreview`
/// runs on the main thread at every step of a scale.
///
/// `NodePropertyBatchCostTests` holds the line by counting.
enum BoardScalePatchBench {
    /// The bench.
    static let bench = Bench(
        name: "board-scale-patch",
        summary: "A whole-board scale's patch and gesture preview on Penumbra's perf board",
        run: { _ in try run() }
    )

    private static func run() throws {
        let document = try EditableDocument(from: PerfBoardFixture.document())
        guard let board = document.rootOrder.first else { return }
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

        try BenchClock.measure("perf board scale per-key setting", runs: 41) {
            for op in patches {
                guard var node = document.node(id: op.nodeID) else { continue }
                for (path, value) in op.properties {
                    node = try NodePropertyCodec.setting(value, at: path, on: node)
                }
            }
        }
        try BenchClock.measure("perf board scale previewNodes", runs: 41) {
            _ = try document.previewNodes(for: plan.operations)
        }
    }
}
