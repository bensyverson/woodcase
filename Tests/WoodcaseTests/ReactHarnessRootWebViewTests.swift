//
//  ReactHarnessRootWebViewTests.swift
//  WoodcaseTests
//

// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// The page ``ReactHarnessBuilder`` writes names its own root so that no component
    /// can take it: a component named `App` — a common page name — used to be drawn by
    /// the harness's `function App()`, which then drew itself forever.
    @Suite("React harness root", .tags(.webViewRegression), .serialized, .hangGuard)
    @MainActor
    struct ReactHarnessRootWebViewTests {
        private static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private let harness = WebViewTestHarness()

        @Test("A component named App renders")
        func appRenders() async throws {
            let name = "App"
            let files = [
                GeneratedFile(path: "theme.css", content: ":root {}"),
                GeneratedFile(
                    path: "components/\(name).tsx",
                    content: """
                    export function \(name)() {
                      return <div style={{ width: 20, height: 20, background: "#ff0000" }} />;
                    }
                    """
                ),
            ]
            let html = ReactHarnessBuilder.buildHTML(
                from: files, componentName: name, viewportWidth: 20, viewportHeight: 20, jsRelativePath: "../js"
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let url = tmpDir.appendingPathComponent("scope-\(name).html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            _ = try await harness.render(
                fileURL: url, viewportSize: CGSize(width: 20, height: 20), allowingReadAccessTo: Self.fixturesDir, timeout: 20
            )
        }
    }

#endif
