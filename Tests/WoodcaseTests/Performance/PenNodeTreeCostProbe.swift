//
//  PenNodeTreeCostProbe.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Foundation
    import Testing
    @testable import Woodcase

    /// What comparing, hashing, encoding, freeing and inserting a node tree cost, printed as `PROBE`
    /// lines: time (median of the runs) and stack high-water, on wide shallow documents
    /// and on deep trees.
    ///
    /// A measurement, not a check — ``PenNodeDeepTreeStackTests`` holds the stack line.
    /// Equality runs on every edit over every top-level node (Penumbra's
    /// `IncrementalExpansion.changedRoots`), so the work-list `==` must not be slower than
    /// the synthesized one it replaced on wide, shallow trees; this is how that was
    /// measured. It runs only when asked; its figures mean something only beside `uptime`:
    ///
    /// ```sh
    /// WOODCASE_TREE_COST_PROBE=1 swift test --filter PenNodeTreeCostProbe
    /// WOODCASE_TREE_COST_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter PenNodeTreeCostProbe
    /// ```
    struct PenNodeTreeCostProbe {
        /// A forest to measure, built fresh by each call so no two share storage.
        private struct Subject {
            let label: String
            let build: () throws -> [PenNode]
        }

        private static var subjects: [Subject] {
            // Penumbra compares two materializations of one flat store on every edit;
            // they share every childless node's storage.
            let mockup = try? EditableDocument(from: DeepDocuments.settingsMockup())
            let app = try? EditableDocument(from: PenParser.parse(contentsOf: PerformanceFixture.largestBundled()))
            return [
                Subject(label: "settings mockup (6 roots, 8 deep)") { try DeepDocuments.settingsMockup().children },
                Subject(label: "settings mockup, materialized") { mockup?.materialize().children ?? [] },
                Subject(label: "woodcase-app, materialized") { app?.materialize().children ?? [] },
                Subject(label: "woodcase-app") { try PenParser.parse(contentsOf: PerformanceFixture.largestBundled()).children },
                Subject(label: "synthetic 5000 nodes") {
                    SyntheticPenDocument.make(nodeCount: PerformanceFixture.syntheticNodeCount).children
                },
                Subject(label: "chain 255") { [DeepDocuments.chain(depth: DeepDocuments.deepestParsableDepth)] },
                Subject(label: "mockup-shaped 253") { try [DeepDocuments.mockupShaped()] },
            ]
        }

        /// Milliseconds in a duration.
        private static func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }

        /// Runs `body` `runs` times, each on a fresh `setUp`: the first on a painted stack
        /// for its high-water, the rest timed. Prints the median time and the stack.
        ///
        /// Everything runs on a thread with a large stack, so the old recursive walks
        /// report a number rather than crash.
        private static func measure<Input>(
            _ label: String,
            runs: Int,
            setUp: @escaping () throws -> Input,
            _ body: @escaping (inout Input?) -> Void
        ) throws {
            let sampled = StackHighWater.measure { () -> Result<(Int, [Duration]), Error> in
                Result {
                    let clock = ContinuousClock()
                    var samples: [Duration] = []
                    var peak = 0
                    for run in 0 ... runs {
                        let held = try Box(setUp())
                        if run == 0 {
                            peak = StackHighWater.measure { body(&held.value) }.bytes
                        } else {
                            samples.append(clock.measure { body(&held.value) })
                        }
                        held.value = nil
                    }
                    return (peak, samples.sorted())
                }
            }
            let (peak, samples) = try sampled.result.get()
            print(String(
                format: "PROBE %@ median %.4f ms stack %d B",
                label, ms(samples[samples.count / 2]), peak
            ))
        }

        /// Somewhere to hand an input to the measured thread.
        private final class Box<Value> {
            var value: Value?

            init(_ value: Value) {
                self.value = value
            }
        }

        @Test(
            "Node tree compare, hash, encode, free and insert cost",
            .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_TREE_COST_PROBE"] != nil)
        )
        func probe() throws {
            for subject in Self.subjects {
                let runs = 9
                try Self.measure("\(subject.label) ==", runs: runs, setUp: { try (subject.build(), subject.build()) }) { pair in
                    guard let (a, b) = pair else { return }
                    precondition(a == b)
                }
                try Self.measure("\(subject.label) hash", runs: runs, setUp: { try subject.build() }) { forest in
                    var hasher = Hasher()
                    hasher.combine(forest)
                    _ = hasher.finalize()
                }
                try Self.measure("\(subject.label) encode", runs: runs, setUp: { try subject.build() }) { forest in
                    _ = try? JSONEncoder().encode(PenDocument(children: forest ?? []))
                }
                try Self.measure("\(subject.label) free", runs: runs, setUp: { try subject.build() }) { forest in
                    forest = nil
                }
                try Self.measure("\(subject.label) insert", runs: runs, setUp: {
                    try (subject.build(), EditableDocument(from: PenDocument(children: [])))
                }) { input in
                    guard let (forest, document) = input else { return }
                    for root in forest {
                        try? document.apply(.insertNode(EditOperation.InsertNode(node: root)))
                    }
                    precondition(document.rootOrder.count == forest.count)
                }
            }
        }
    }
#endif
