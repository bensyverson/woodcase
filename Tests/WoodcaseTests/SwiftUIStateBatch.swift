//
//  SwiftUIStateBatch.swift
//  WoodcaseTests
//

// macOS-only: it shells out to Xcode's toolchain, and the harness links SwiftUI.
#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// One compile and one render of `codegen-states.pen`'s components as the SwiftUI emitter
    /// writes them, each drawn in the states Pen exports a `:state` sibling frame for — the
    /// state pinned the way a caller pins it (`.penControlState(.pressed)`, `.disabled(true)`,
    /// `isOn: .constant(false)`) — built by one `xcrun swiftc -Onone` child at the default
    /// floor and type-checked at iOS 18 / macOS 15 beside it, as ``SwiftUIScreenBatch`` does
    /// for the `woodcase-app` screens.
    enum SwiftUIStateBatch {
        /// One state of one component: the call that draws it and Pen's export it is measured
        /// against.
        struct Board: Friendly, CustomTestStringConvertible {
            /// The render's name, and the reference's after `codegen-states-`.
            var name: String
            /// The Swift expression that draws the state.
            var view: String

            var testDescription: String {
                name
            }

            /// Pen's export of the frame, without `.png`.
            var referenceName: String {
                "codegen-states-\(name)"
            }
        }

        /// Every board: each component's default state, and each state Pen draws a sibling
        /// frame for that a caller can pin. The text field is left out: `ImageRenderer` draws
        /// a platform-backed `TextField` as a placeholder symbol.
        static let boards: [Board] = [
            Board(name: "StatesButton", view: "StatesButton()"),
            Board(name: "StatesButton-pressed", view: "StatesButton().penControlState(.pressed)"),
            Board(name: "StatesButton-disabled", view: "StatesButton().disabled(true)"),
            Board(name: "StatesButton-hover", view: "StatesButton().penControlState(.hovered)"),
            Board(name: "Switch", view: "Switch()"),
            Board(name: "Switch-off", view: "Switch(isOn: .constant(false))"),
            Board(name: "SortSelect", view: "SortSelect()"),
            Board(name: "SortSelect-open", view: "SortSelect(variant: .open)"),
            Board(name: "MoreLink", view: "MoreLink()"),
            Board(name: "Chip", view: "Chip()"),
            Board(name: "Chip-selected", view: "Chip(variant: .selected)"),
        ]

        /// What the batch produced.
        struct Outcome {
            /// Where the harness wrote `<board>.png`, when the build and the render ran.
            var renders: URL?
            /// The build's or the harness run's failure output, if either failed.
            var buildFailure: String?
            /// The lower floor's type-check failure output, if it failed.
            var lowerFloorFailure: String?
        }

        /// Pixels per point of Pen's exports (`scripts/pen-oracle`'s default).
        static let scale = 2

        /// The batch, built on first use and shared by every test in the process.
        static let shared: Task<Outcome, Error> = Task { try await run() }

        private static func run() async throws -> Outcome {
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-states-\(UUID().uuidString.prefix(8))")
            let sources = root.appendingPathComponent("Sources")
            let renders = root.appendingPathComponent("renders")
            for directory in [sources, renders] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let result = try SwiftUIFixtures.emit("codegen-states")
            // The library's files only: the catalog executable's main.swift would be a second
            // top-level main beside the harness's.
            for file in result.files where file.path.hasSuffix(".swift") && file.path.hasPrefix("Sources/PenUI/") {
                let name = URL(fileURLWithPath: file.path).lastPathComponent
                try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let entries = boards.map { "        (\"\($0.name)\", \(scale), AnyView(\($0.view)))," }
            // The package's resources: none, but the support files read `Bundle.module`.
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
            async let build = SwiftUIRenderBatch.runAsync(
                SwiftUIRenderBatch.compile(floor: SwiftUIEmitter.Options().deploymentFloor)
                    + ["-Onone", "-module-name", "PenHarness", "-o", binary] + files,
                log: root.appendingPathComponent("build.log")
            )
            async let check = SwiftUIRenderBatch.runAsync(
                SwiftUIRenderBatch.compile(floor: .iOS18) + ["-typecheck", "-module-name", "PenHarness"] + files,
                log: root.appendingPathComponent("typecheck.log")
            )
            let (built, checked) = try await (build, check)
            let lowerFloorFailure = checked.succeeded ? nil : checked.output
            guard built.succeeded else { return Outcome(buildFailure: built.output, lowerFloorFailure: lowerFloorFailure) }
            let inter = WoodcaseHome.directory().appendingPathComponent("fonts/inter").path
            let rendered = try await SwiftUIRenderBatch.runAsync(
                [binary, renders.path, inter, SwiftUIRenderBatch.testFonts.path],
                log: root.appendingPathComponent("render.log")
            )
            guard rendered.succeeded else {
                return Outcome(
                    buildFailure: rendered.status.map { "the harness exited \($0):\n\(rendered.output)" } ?? rendered.output,
                    lowerFloorFailure: lowerFloorFailure
                )
            }
            return Outcome(renders: renders, lowerFloorFailure: lowerFloorFailure)
        }
    }

#endif
