// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links
// AppKit and the Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers
    @testable import Woodcase

    @Suite("WebViewTestHarness", .hangGuard)
    @MainActor
    struct WebViewTestHarnessTests {
        private let harness = WebViewTestHarness()

        private let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("webview-harness-tests")

        /// Writes HTML to a temp file and renders it via the harness.
        ///
        /// The budget is the harness's own, so every test that expects a page to
        /// *work* shares one pool bucket and one "this is hung" scale. A test that
        /// expects a timeout passes its own.
        private func renderHTML(
            _ html: String,
            viewport: CGSize,
            timeout: TimeInterval = WebViewTestHarness.defaultBudget
        ) async throws -> CGImage {
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let fileURL = tmpDir.appendingPathComponent("test-\(UUID().uuidString).html")
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            return try await harness.render(
                fileURL: fileURL,
                viewportSize: viewport,
                allowingReadAccessTo: tmpDir,
                timeout: timeout
            )
        }

        /// HTML exercising every way an icon glyph reaches the page: a CSS-class
        /// ligature, a raw codepoint, inline-style variants of both, and both set
        /// via JavaScript after load — against the bundled lucide font at `fontURL`.
        private static func iconTestHTML(fontURL: URL) -> String {
            """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
            @font-face {
              font-family: 'lucide';
              src: url('\(fontURL.absoluteString)') format('truetype');
            }
            .icon {
              font-family: 'lucide';
              font-size: 48px;
              font-feature-settings: "liga" 1;
              -webkit-font-smoothing: antialiased;
              text-rendering: optimizeLegibility;
            }
            </style>
            </head>
            <body style="padding: 20px; font-size: 16px;">
            <p>Test 1 - Ligature via CSS class:</p>
            <span class="icon">heart</span>

            <p>Test 2 - Codepoint U+E0F2:</p>
            <span class="icon">&#xE0F2;</span>

            <p>Test 3 - Inline style ligature:</p>
            <span style="font-family: lucide; font-size: 48px; font-feature-settings: 'liga' 1;">heart</span>

            <p>Test 4 - Inline style codepoint:</p>
            <span style="font-family: lucide; font-size: 48px;">&#xE0F2;</span>

            <p>Test 5 - JS-set codepoint:</p>
            <span id="t5" style="font-family: lucide; font-size: 48px;"></span>

            <p>Test 6 - JS-set ligature:</p>
            <span id="t6" style="font-family: lucide; font-size: 48px; font-feature-settings: 'liga' 1;">loading...</span>

            <script>
            document.getElementById('t5').textContent = "\\uE0F2";
            document.getElementById('t6').textContent = "heart";
            document.fonts.load('48px lucide').then(function() {
              console.log('Font loaded');
              window.__READY__ = true;
            });
            </script>
            </body>
            </html>
            """
        }

        @Test("Renders trivial HTML and returns screenshot with correct dimensions")
        func trivialHTMLRender() async throws {
            let html = """
            <html>
            <body style="margin:0; padding:0;">
            <div style="background:red; width:100px; height:100px;"></div>
            <script>window.__READY__ = true;</script>
            </body>
            </html>
            """
            let viewport = CGSize(width: 200, height: 200)
            let image = try await renderHTML(html, viewport: viewport)
            // WKWebView returns @2x on Retina; dimensions should be a whole multiple of viewport
            #expect(image.width > 0)
            #expect(image.height > 0)
            #expect(image.width % Int(viewport.width) == 0)
            #expect(image.height % Int(viewport.height) == 0)
        }

        @Test("Renders HTML with delayed __READY__ signal")
        func delayedReadySignal() async throws {
            let html = """
            <html>
            <body style="margin:0; padding:0;">
            <div id="box" style="background:blue; width:50px; height:50px;"></div>
            <script>
            setTimeout(function() {
                window.__READY__ = true;
                window.webkit.messageHandlers.ready.postMessage("ready");
            }, 100);
            </script>
            </body>
            </html>
            """
            let viewport = CGSize(width: 100, height: 100)
            let image = try await renderHTML(html, viewport: viewport)
            #expect(image.width > 0)
            #expect(image.height > 0)
            #expect(image.width % Int(viewport.width) == 0)
        }

        @Test("Screenshot captures visible content")
        func capturesVisibleContent() async throws {
            let html = """
            <html>
            <body style="margin:0; padding:0;">
            <div style="background:red; width:100px; height:50px;"></div>
            <div style="background:blue; width:100px; height:50px;"></div>
            <script>window.__READY__ = true;</script>
            </body>
            </html>
            """
            let image = try await renderHTML(html, viewport: CGSize(width: 100, height: 100))
            #expect(image.width > 0)
            #expect(image.height > 0)
        }

        @Test("Icon font renders glyphs via file URL")
        func iconFontFileURL() async throws {
            let fixturesTmp = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("tmp")
            let projectRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()

            // Reference the actual bundled font — the same file CoreText registration
            // uses — rather than a hand-copied fixture, so this test also proves the
            // packaged resource is where the registry expects it to be.
            let lucideFontURL = try #require(
                PenIconFontRegistry.shared.fontFileURLs(for: "lucide").first,
                "Bundle.module should resolve the bundled lucide.ttf"
            )

            try FileManager.default.createDirectory(at: fixturesTmp, withIntermediateDirectories: true)
            let fileURL = fixturesTmp.appendingPathComponent("icon-test.html")
            try Self.iconTestHTML(fontURL: lucideFontURL).write(to: fileURL, atomically: true, encoding: .utf8)

            let image = try await harness.render(
                fileURL: fileURL,
                viewportSize: CGSize(width: 400, height: 600),
                allowingReadAccessTo: projectRoot
            )
            // Save for visual inspection
            let outURL = TestOutputDirectory.webViewRegressionURL.appendingPathComponent("icon-test.png")
            try? FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let dest = CGImageDestinationCreateWithURL(
                outURL as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("  Saved icon test: \(outURL.path)")
            #expect(image.width > 0)
        }

        /// A page that throws must fail as `.javaScriptError`, not as a timeout:
        /// the harness sets `__READY__` itself on an uncaught error so the
        /// failure names its cause instead of sitting out the budget.
        ///
        /// The message is only asserted to be non-empty. WebKit sanitizes
        /// `ErrorEvent.message` to `"Script error."` for a `file:` document,
        /// whose scripts carry an opaque origin — so does an unhandled
        /// rejection's reason.
        ///
        /// It renders on the default budget rather than a short one. The distinction
        /// this test draws is between two *typed* errors, and a budget the machine's
        /// load can spend turns the right answer into the wrong one: at five seconds
        /// this failed a loaded soak with "Expected .javaScriptError, got WebView
        /// timed out waiting for __READY__ signal", which says only that five seconds
        /// were not enough.
        @Test("Surfaces an uncaught JavaScript error rather than timing out")
        func uncaughtJavaScriptErrorSurfaces() async {
            let html = """
            <html>
            <body style="margin:0; padding:0;">
            <script>throw new Error("boom");</script>
            </body>
            </html>
            """
            do {
                _ = try await renderHTML(html, viewport: CGSize(width: 100, height: 100))
                Issue.record("Expected the harness to throw for an uncaught page error")
            } catch let error as WebViewTestHarness.HarnessError {
                guard case let .javaScriptError(message) = error else {
                    Issue.record("Expected .javaScriptError, got \(error)")
                    return
                }
                #expect(!message.isEmpty)
            } catch {
                Issue.record("Expected a HarnessError, got \(error)")
            }
        }

        @Test("Times out when __READY__ never fires")
        func timeoutWhenNoReady() async {
            let html = """
            <html>
            <body><p>No ready signal here</p></body>
            </html>
            """
            await #expect(throws: WebViewTestHarness.HarnessError.self) {
                try await renderHTML(html, viewport: CGSize(width: 100, height: 100), timeout: 2.0)
            }
        }
    }

#endif
