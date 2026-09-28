//
//  PerformanceShotBudgetTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Holds the render of one artboard — what `woodcase shot` writes — to its budget.
    ///
    /// `shot` is the most expensive read the CLI offers and the one a caller reaches for
    /// when the cheap structural answers have not settled a question, so a second is the
    /// ceiling: past that it stops being a thing you do mid-conversation. The whole
    /// pipeline is timed — the shared lock, the parse, address resolution, ref expansion,
    /// variable resolution, layout, the CoreGraphics render, and the PNG on disk.
    ///
    /// ## Warm, and what that excludes
    ///
    /// The budget is a **warm** one, which is what ``PerformanceSample/best`` measures:
    /// the first repetition pays for CoreText's font state and the file system's page
    /// cache, and the minimum reports the steady state. It excludes
    /// ``GoogleFontResolver/prepareFonts(for:)``, which `shot` calls before rendering —
    /// that is a network download on a cold cache, is a no-op once warm, and putting the
    /// network inside a budget test would make it fail for reasons that are not ours.
    /// The doc records the binary's end-to-end time, which does include it.
    @MainActor
    struct ShotTests {
        /// The longest side `shot` defaults to, in points.
        private static let maxSize: Double = 1600

        /// 1 s for one artboard of the largest real document, warm — the leaf's number.
        private static let budget = PerformanceBudget(
            name: "shot of one artboard of woodcase-app.pen",
            release: .seconds(1)
        )

        /// The **same** ceiling for the synthetic document's first artboard, which at
        /// 1601 nodes is several times the size of any artboard in a real file.
        ///
        /// Unlike `tree` and `set`, this one needs no allowance: a render of 1601 nodes
        /// came in at 272 ms release-equivalent on 2026-08-29, well inside the second
        /// the leaf asks for, so the leaf's number stands as written.
        private static let syntheticBudget = PerformanceBudget(
            name: "shot of one artboard of a synthetic \(PerformanceFixture.syntheticNodeCount)-node document",
            release: .seconds(1)
        )

        @Test("A shot of one artboard of the largest real fixture stays under budget")
        func shotOfLargestFixture() async throws {
            let url = try PerformanceFixture.largestBundled()
            let output = try PerformanceFixture.scratchFile(named: "shot.png")
            defer { PerformanceFixture.discard(output) }
            let node = try await Self.firstArtboardName(of: url)
            try await Self.check(Self.budget, node: node, in: url, to: output)
        }

        @Test("A shot of one artboard of a 5000-node synthetic document stays under budget")
        func shotOfSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            let output = url.deletingLastPathComponent().appendingPathComponent("shot.png")
            let node = try await Self.firstArtboardName(of: url)
            #expect(node == SyntheticPenDocument.firstArtboardName)
            try await Self.check(Self.syntheticBudget, node: node, in: url, to: output)
        }

        // MARK: - The pipeline

        /// Measures `budget.repetitions` renders and asserts the minimum.
        ///
        /// - Parameters:
        ///   - budget: The ceiling to hold the minimum to.
        ///   - node: The artboard to render, by name.
        ///   - url: The `.pen` file to read.
        ///   - output: Where the PNG goes; overwritten every repetition.
        /// - Throws: Whatever the pipeline throws.
        private static func check(
            _ budget: PerformanceBudget,
            node: String,
            in url: URL,
            to output: URL
        ) async throws {
            let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
                try await shot(node: node, in: url, to: output)
            }
            #expect(FileManager.default.fileExists(atPath: output.path), "The render wrote no PNG.")
            budget.check(sample)
        }

        /// Everything `woodcase shot <file> <node> --out <png>` does, less font downloads.
        ///
        /// - Parameters:
        ///   - node: The node to render, in any form ``EditableDocument/resolve(_:tags:)``
        ///     accepts.
        ///   - url: The `.pen` file to read.
        ///   - output: Where to write the PNG.
        /// - Throws: An expectation failure when the node has no layout rect or the render
        ///   produces no image; whatever the transaction, layout or encoder throws.
        private static func shot(node: String, in url: URL, to output: URL) async throws {
            let selection = try await PenFileTransaction.read(at: url) { document in
                let resolved = try document.resolve(node)
                return Selection(
                    document: document.materialize(), nodeID: document.expandedID(of: resolved)
                )
            }.value

            let expanded = PenRefExpander.expand(selection.document)
            let resolved = PenVariableResolver.resolve(expanded, theme: [:])
            let rects = PenLayoutEngine.layout(resolved)
            let renderID = selection.nodeID
            let rect = try #require(rects[renderID], "\(node) has no computed layout rect.")

            let longest = max(rect.width, rect.height)
            let scale = longest > 0 ? min(1, maxSize / longest) : 1
            let image = try #require(
                PenRenderer.render(
                    resolved,
                    layoutRects: rects,
                    size: CGSize(width: rect.width, height: rect.height),
                    scale: CGFloat(scale),
                    rootNodeID: renderID,
                    imageProvider: PenRenderer.fileImageProvider(relativeTo: url.deletingLastPathComponent())
                ),
                "The renderer produced no image for \(node)."
            )
            try PNGEncoder.write(image, to: output)
        }

        /// The name of the document's first *placed* artboard, so no test hard-codes an id
        /// out of a fixture that may be re-authored.
        ///
        /// A top-level node marked `reusable` is a component *definition*, not something on
        /// the canvas: ``PenRefExpander`` drops definitions from the expanded tree, so they
        /// get no layout rect and cannot be rendered. `woodcase-app.pen` is entirely made
        /// of them — every one of its nine top-level frames is a definition, and its eight
        /// artboards are the `ref` nodes that place them — so "the first top-level frame"
        /// would have picked the one thing in the file that is not renderable.
        ///
        /// - Parameter url: The `.pen` file to read.
        /// - Returns: The node's name, or its `#id` marker when it has none.
        /// - Throws: An expectation failure for a document with nothing placed on the canvas.
        private static func firstArtboardName(of url: URL) async throws -> String {
            try await PenFileTransaction.read(at: url) { document in
                let placed = document.rootOrder.first { candidate in
                    document.nodes[candidate]?.common.reusable != true
                }
                let id = try #require(
                    placed,
                    "\(url.lastPathComponent) has no placed artboard — every root node is reusable."
                )
                return document.nodes[id]?.common.name ?? NodeAddress.marker(forID: id)
            }.value
        }

        /// What the read transaction hands the render: the materialized document and the
        /// id to draw.
        private struct Selection {
            /// The document, before ref expansion or variable resolution.
            var document: PenDocument

            /// The id to render, in the form ref expansion produces — the same
            /// ``EditableDocument/expandedID(of:)`` `woodcase shot` renders by.
            var nodeID: String
        }
    }
}
