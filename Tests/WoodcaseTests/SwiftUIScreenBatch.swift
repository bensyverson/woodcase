//
//  SwiftUIScreenBatch.swift
//  WoodcaseTests
//

// macOS-only: it shells out to Xcode's toolchain, and the harness links SwiftUI.
#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// One compile and one render of the `woodcase-app.pen` screens as the SwiftUI emitter
    /// writes them: every component file of the fixture, the support files and the render
    /// harness in one module, built by one `xcrun swiftc -Onone` child at the default floor and
    /// type-checked at iOS 18 / macOS 15 beside it
    /// (``SwiftUIRenderBatch`` does the same for the fixture boards, and lends its runner).
    ///
    /// The screens are reusable components in the fixture, and Pen exports each through a
    /// top-level instance of it: `Ratings (Light)`, `Ratings (Dark)` with `theme: {mode:
    /// dark}`, `Settings (Compact)` with `{density: compact}`. The fixture is emitted as it is,
    /// its variables unresolved, with each such instance passed as a page, so a screen renders
    /// exactly as the emitter writes that instance — a call to the screen's view struct under
    /// the instance's theme (`.penTheme(mode: .dark)`), every variable read through `PenTheme`.
    enum SwiftUIScreenBatch {
        /// A screen of the fixture: the reference it is measured against, the component that
        /// draws it and the instance Pen exported it through.
        struct Screen: Friendly, CustomTestStringConvertible {
            /// The reference's name after `woodcase-app-`, and the render's.
            var name: String
            /// The reusable frame the screen is.
            var componentID: String
            /// The top-level instance of it Pen exported, which sets its theme.
            var instanceID: String

            var testDescription: String {
                name
            }

            /// Pen's export, without `.png`.
            var referenceName: String {
                "woodcase-app-\(name)"
            }

            /// The page the instance is emitted as: `RenderRatingsDark`.
            var pageName: String {
                "Render" + name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            }
        }

        /// What the batch produced.
        struct Outcome {
            /// Where the harness wrote `<screen>.png`, when the build and the render ran.
            var renders: URL?
            /// The build's or the harness run's failure output, if either failed.
            var buildFailure: String?
            /// The lower floor's type-check failure output, if it failed.
            var lowerFloorFailure: String?
        }

        /// Every screen with a Pen export, in each theme it was exported in.
        static let screens: [Screen] = [
            Screen(name: "home-collection", componentID: "ydnjs", instanceID: "GkyjX"),
            Screen(name: "home-collection-dark", componentID: "ydnjs", instanceID: "FH8Qz"),
            Screen(name: "usage-log", componentID: "tcjjA", instanceID: "NZV2n"),
            Screen(name: "usage-log-dark", componentID: "tcjjA", instanceID: "553Ui"),
            Screen(name: "ratings", componentID: "ifBcZ", instanceID: "X1KWu"),
            Screen(name: "ratings-dark", componentID: "ifBcZ", instanceID: "Pui09"),
            Screen(name: "wishlist", componentID: "XQ4l7", instanceID: "it5ZZ"),
            Screen(name: "wishlist-dark", componentID: "XQ4l7", instanceID: "XmYkF"),
            Screen(name: "settings", componentID: "BTvzs", instanceID: "vD6Pn"),
            Screen(name: "settings-dark", componentID: "BTvzs", instanceID: "pkh1K"),
            Screen(name: "settings-compact", componentID: "BTvzs", instanceID: "HvIEx"),
            Screen(name: "settings-compact-dark", componentID: "BTvzs", instanceID: "QGQZC"),
            Screen(name: "lab", componentID: "ld7Yp", instanceID: "f3f7e"),
            Screen(name: "lab-dark", componentID: "ld7Yp", instanceID: "VzViF"),
        ]

        /// The batch, built on first use and shared by every test in the process.
        static let shared: Task<Outcome, Error> = Task { try await run() }

        private static func run() async throws -> Outcome {
            let root = TestOutputDirectory.url.appendingPathComponent("swiftui-screens-\(UUID().uuidString.prefix(8))")
            let sources = root.appendingPathComponent("Sources")
            let renders = root.appendingPathComponent("renders")
            let bundle = root.appendingPathComponent("PenHarness.bundle")
            for directory in [sources, renders, bundle] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let document = try SwiftUIFixtures.document("woodcase-app")
            let components = ComponentAnalyzer.analyze(document)
            let pages = try screens.map { screen in
                let instance = try #require(document.children.first { $0.id == screen.instanceID }, "no instance \(screen.instanceID)")
                return PageDefinition(id: screen.instanceID, name: screen.pageName, sourceNode: instance)
            }
            let result = try SwiftUIEmitter.emit(
                document: document, components: components, pages: pages, theme: ThemeAnalyzer.analyze(document)
            )
            // The library's files only: the catalog executable's main.swift would be a second
            // top-level main beside the harness's.
            for file in result.files where file.path.hasSuffix(".swift") && file.path.hasPrefix("Sources/PenUI/") {
                let name = URL(fileURLWithPath: file.path).lastPathComponent
                try file.content.write(to: sources.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let resources = result.imageAssetURLs.sorted().map { SwiftUIFixtures.directory.appendingPathComponent($0) }
                + result.iconLibraries.sorted().flatMap(SwiftUIEmitter.iconFontFiles(for:))
            for source in resources {
                let target = bundle.appendingPathComponent(source.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: source, to: target)
                }
            }

            var entries: [String] = []
            for screen in screens {
                try entries.append("        (\"\(screen.name)\", \(scale(of: screen, in: document)), AnyView(\(screen.pageName)())),")
            }
            let boards = """
            import Foundation
            import SwiftUI

            \(SwiftUIRenderBatch.bundleShim(at: bundle))
            @MainActor func renderBoards() -> [(name: String, scale: CGFloat, view: AnyView)] {
                [
            \(entries.joined(separator: "\n"))
                ]
            }

            """
            try boards.write(to: sources.appendingPathComponent("Boards.swift"), atomically: true, encoding: .utf8)
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

        /// The reference's pixels per point: its width over the screen component's.
        private static func scale(of screen: Screen, in document: PenDocument) throws -> Int {
            let reference = try #require(
                PenSnapshotTestHelpers.loadFixtureImage(named: screen.referenceName, fixturesDir: SwiftUIFixtures.directory)
            )
            let root = try #require(document.children.first { $0.id == screen.componentID })
            guard case let .fixed(width) = PenLayoutEngine.widthSizing(of: root), width > 0 else { return 1 }
            return max(1, Int((Double(reference.width) / width).rounded()))
        }
    }

#endif
