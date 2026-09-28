//
//  SwiftUIThemedNumbersBatch.swift
//  WoodcaseTests
//

// macOS-only: it shells out to Xcode's toolchain, and the harness links SwiftUI.
#if os(macOS)

    import Foundation
    @testable import Woodcase

    /// One compile and one render of `render-themed-numbers`'s two boards — a shadow's blur,
    /// a rotation, a gradient stop and a per-side stroke width, each a variable that differs
    /// by theme — in a batch of its own.
    ///
    /// The shared ``SwiftUIRenderBatch`` holds one `PenTheme` for the whole run
    /// (`swiftui-color-scheme` already claims that slot: "two themed fixtures must agree on
    /// it"), so a second themed fixture needs its own module rather than colliding with it.
    /// Built by one `xcrun swiftc -Onone` child, like ``SwiftUISlotBatch``.
    enum SwiftUIThemedNumbersBatch {
        /// The light and dark boards.
        static let boards = [
            SwiftUIRenderBoard(fixture: "render-themed-numbers", artboard: "themed-numbers-light"),
            SwiftUIRenderBoard(fixture: "render-themed-numbers", artboard: "themed-numbers-dark"),
        ]

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
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-themed-numbers-\(UUID().uuidString.prefix(8))")
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
                let scale = try board.referenceScale()
                entries.append("        (\"\(board.id)\", \(scale), AnyView(\(type)())),")
                if support.isEmpty { support = emitted.support }
                for file in emitted.theme {
                    let name = URL(fileURLWithPath: file.path).lastPathComponent
                    try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
                }
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
            let inter = WoodcaseHome.directory().appendingPathComponent("fonts/inter").path
            let rendered = try await SwiftUIRenderBatch.runAsync(
                [binary, renders.path, inter, SwiftUIRenderBatch.testFonts.path],
                log: root.appendingPathComponent("render.log")
            )
            guard rendered.succeeded else {
                return Outcome(buildFailure: rendered.status.map { "the harness exited \($0):\n\(rendered.output)" } ?? rendered.output)
            }
            return Outcome(renders: renders)
        }
    }

#endif
