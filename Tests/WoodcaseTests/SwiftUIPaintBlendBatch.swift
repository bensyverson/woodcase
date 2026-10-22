//
//  SwiftUIPaintBlendBatch.swift
//  WoodcaseTests
//

// macOS-only: it shells out to Xcode's toolchain, and the harness links SwiftUI.
#if os(macOS)

    import Foundation
    @testable import Woodcase

    /// One compile and one render of the paint-blend boards — `paint-blend-stacks`, which
    /// React's paint blend gate draws too, and `paint-blend-frames` — in a batch of their own.
    ///
    /// Pen exported no PNGs of these: Pen blends a paint with whatever lies behind its node,
    /// where Woodcase keeps it within the node's own paints (Ben's reading-1 ruling,
    /// 2026-10-20), so the boards are measured against the CG renderer, not Pen, and do not
    /// belong in ``SwiftUIRenderBatch``, whose boards are each measured against Pen's export.
    /// Built by one `xcrun swiftc -Onone` child, like ``SwiftUIThemedNumbersBatch``.
    enum SwiftUIPaintBlendBatch {
        /// The pixels per point every board renders at.
        static let scale = 2

        /// Every artboard of the two fixtures.
        static let boards: [SwiftUIRenderBoard] = ["paint-blend-stacks", "paint-blend-frames"].flatMap { fixture in
            let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
            return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }
        }

        /// What the batch produced.
        struct Outcome {
            /// Where the harness wrote `<board id>.png`, when the build and the render ran.
            var renders: URL?
            /// The build's or the harness run's failure output, if either failed.
            var buildFailure: String?
        }

        /// The batch, built on first use and shared by every test in the process.
        static let shared: Task<Outcome, Error> = Task { try await run() }

        private static func run() async throws -> Outcome {
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-paint-blend-\(UUID().uuidString.prefix(8))")
            let sources = root.appendingPathComponent("Sources")
            let renders = root.appendingPathComponent("renders")
            for directory in [sources, renders] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            var entries: [String] = []
            var support: [GeneratedFile] = []
            for (index, board) in boards.enumerated() {
                let type = "Board\(index)"
                let emitted = try board.emitPage(named: type)
                try emitted.page.content.write(to: sources.appendingPathComponent("\(type).swift"), atomically: true, encoding: .utf8)
                entries.append("        (\"\(board.id)\", \(scale), AnyView(\(type)())),")
                if support.isEmpty { support = emitted.support }
            }
            for file in support {
                let name = URL(fileURLWithPath: file.path).lastPathComponent
                try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }

            let bundle = root.appendingPathComponent("PenHarness.bundle")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let listing = """
            import SwiftUI

            \(SwiftUIRenderBatch.bundleShim(at: bundle))
            @MainActor func renderBoards() -> [(name: String, scale: CGFloat, view: AnyView)] {
                [
            \(entries.joined(separator: "\n"))
                ]
            }

            """
            try listing.write(to: sources.appendingPathComponent("Boards.swift"), atomically: true, encoding: .utf8)
            let harness = SwiftUIFixtures.directory.appendingPathComponent("swiftui-harness/main.swift")
            try FileManager.default.copyItem(at: harness, to: sources.appendingPathComponent("main.swift"))

            let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
                .filter { $0.hasSuffix(".swift") }.sorted()
                .map { sources.appendingPathComponent($0).path }
            let binary = root.appendingPathComponent("harness").path
            let built = try await SwiftUIRenderBatch.runAsync(
                SwiftUIRenderBatch.compile(floor: SwiftUIEmitter.Options().deploymentFloor)
                    + ["-Onone", "-module-name", "PenHarness", "-o", binary] + files,
                log: root.appendingPathComponent("build.log")
            )
            guard built.succeeded else { return Outcome(buildFailure: built.output) }
            let rendered = try await SwiftUIRenderBatch.runAsync(
                [binary, renders.path, SwiftUIRenderBatch.testFonts.path],
                log: root.appendingPathComponent("render.log")
            )
            guard rendered.succeeded else {
                return Outcome(buildFailure: rendered.status.map { "the harness exited \($0):\n\(rendered.output)" } ?? rendered.output)
            }
            return Outcome(renders: renders)
        }
    }

#endif
