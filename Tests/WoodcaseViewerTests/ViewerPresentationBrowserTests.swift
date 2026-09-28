//
//  ViewerPresentationBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// Presentation mode, measured rather than described.
    ///
    /// The mode's whole claim is about *size and nothing else*: the artboard as large as
    /// the screen allows, on its background, with every piece of chrome gone. Both halves
    /// of that are facts about boxes on a real screen — a class on `<body>` says nothing
    /// about whether the render actually grew — so this suite reads
    /// `getBoundingClientRect` and the computed `--v-scale` back out of a live page.
    ///
    /// Its own suite, like ``ViewerNavigationBrowserTests``: a headless page plus a live
    /// server is heavy enough that two suites sharing one bench contend.
    @Suite(.serialized, .hangGuard)
    struct ViewerPresentationBrowserTests {
        /// A server and a page pointed at it.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            /// - Parameter fixture: The .pen file to serve. `batch.pen` has three
            ///   artboards, so there is somewhere to step to while presenting.
            init(fixture: String = "batch.pen") async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy(fixture, into: scratch)
                log = ActivityLog(home: scratch)
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [file], port: 0, log: log)
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1600, height: 900),
                    wait: .load,
                    budget: 20
                ))
            }

            var fileID: String {
                ViewerFile(url: file).id
            }

            func url(_ path: String) -> URL {
                URL(string: "http://localhost:\(port)\(path)")!
            }

            func ask(_ body: String) async -> String {
                guard let json = try? await host.boundedEvaluate(body, in: .page) else { return "" }
                guard let decoded = try? JSONSerialization.jsonObject(
                    with: Data(json.utf8), options: [.fragmentsAllowed]
                ) as? String else { return json }
                return decoded
            }

            func waitFor(
                _ description: Comment,
                _ body: String,
                within bound: Duration = .seconds(30)
            ) async {
                let deadline = ContinuousClock.now + bound
                while ContinuousClock.now < deadline {
                    if await ask(body) == "true" { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                Issue.record("timed out waiting for \(description)")
            }

            func pressKey(_ key: String) async {
                _ = await ask("""
                document.dispatchEvent(new KeyboardEvent('keydown', { key: '\(key)', bubbles: true, cancelable: true }));
                return 'ok';
                """)
            }

            /// Whether the stage is drawn at the biggest scale this screen allows.
            ///
            /// The answer the script should have written: the viewport less the stage's
            /// own margin, capped at the density the PNG was rendered at — past that the
            /// image is being enlarged past its own pixels, which is blur, not size.
            func stageFit() async -> String {
                await ask("""
                const stage = document.getElementById('v-stage');
                const w = parseFloat(stage.style.getPropertyValue('--v-art-w'));
                const h = parseFloat(stage.style.getPropertyValue('--v-art-h'));
                const density = parseFloat(stage.dataset.density);
                const want = Math.min(density, (innerWidth - 24) / w, (innerHeight - 24) / h);
                const got = parseFloat(getComputedStyle(stage).getPropertyValue('--v-scale'));
                return Math.abs(got - want) < 0.02 ? 'fitted' : `scale ${got}, wanted ${want}`;
                """)
            }

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        @MainActor
        @Test("Presentation shows the artboard on its background and nothing else")
        func presentationShowsOnlyTheArtboard() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Ttl01")
            )
            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )

            for selector in [".v-topbar", ".v-side", ".v-grip", ".v-selection", "#v-overlay"] {
                #expect(
                    await bench.ask(
                        "return getComputedStyle(document.querySelector('\(selector)')).display;"
                    ) == "none",
                    "\(selector) should be hidden while presenting"
                )
            }
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-render')).display;") != "none")

            // The artboard's background is the whole screen: the canvas covers the
            // viewport, so there is no strip of chrome-coloured nothing at any edge.
            #expect(await bench.ask("""
            const box = document.querySelector('.v-canvas').getBoundingClientRect();
            const full = box.width >= innerWidth - 1 && box.height >= innerHeight - 1
              && box.top <= 1 && box.left <= 1;
            return full ? 'full' : `${box.width}x${box.height} at ${box.left},${box.top}`;
            """) == "full")
        }

        @MainActor
        @Test("The artboard grows to the screen, up to the density its PNG was rendered at")
        func presentationRefitsTheArtboardToTheScreen() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            let before = await bench.ask("""
            return String(document.getElementById('v-stage').getBoundingClientRect().width);
            """)

            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )

            #expect(await bench.stageFit() == "fitted")
            // And bigger than it was in the three-pane layout, which is the visible
            // claim: the mode is for looking at the design, not at the furniture.
            let after = await bench.ask("""
            return String(document.getElementById('v-stage').getBoundingClientRect().width);
            """)
            #expect((Double(after) ?? 0) > (Double(before) ?? .infinity))
        }

        @MainActor
        @Test("An exit hint flashes on entry and then fades")
        func presentationFlashesTheExitHint() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            #expect(await bench.ask(
                "return getComputedStyle(document.getElementById('v-present-hint')).display;"
            ) == "none", "the hint is not on the page until the mode is")

            await bench.pressKey("f")
            await bench.waitFor(
                "the exit hint to flash",
                "return getComputedStyle(document.getElementById('v-present-hint')).opacity === '1';"
            )
            #expect(await bench.ask(
                "return document.getElementById('v-present-hint').textContent.trim();"
            ) == PresentationHint.text)

            // The script lets go of the hint after its lifetime, and the stylesheet
            // transitions it out from there. The *class* is what is asserted rather than
            // the opacity it ends on: a headless page is not on a screen, and a renderer
            // that is not painting need not advance a transition, so a test that waited
            // for `opacity: 0` would be testing WebKit's throttling rather than this.
            await bench.waitFor(
                "the exit hint to be let go of",
                "return !document.getElementById('v-present-hint').classList.contains('is-flashing');"
            )
            #expect(ViewerStylesheet.css.contains("transition: opacity 0.6s ease-out"))
            // Leaving and coming back flashes it again: it is a reminder, not a one-off.
            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to disengage",
                "return document.body.classList.contains('is-presenting') === false;"
            )
            await bench.pressKey("f")
            await bench.waitFor(
                "the exit hint to flash a second time",
                "return getComputedStyle(document.getElementById('v-present-hint')).opacity === '1';"
            )
        }

        @MainActor
        @Test("The top bar's button enters presentation without the keyboard")
        func theTopBarButtonEntersPresentation() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            #expect(await bench.ask("return document.body.classList.contains('is-presenting');") == "false")

            _ = await bench.ask("document.getElementById('v-present').click(); return 'ok';")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )
            #expect(await bench.stageFit() == "fitted")
        }

        @MainActor
        @Test("Stepping to another artboard while presenting stays in the mode, refitted")
        func steppingWhilePresentingStaysFitted() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the second artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            #expect(await bench.ask("return document.body.classList.contains('is-presenting');") == "true")
            // A different artboard is a different size, so staying in the mode is only
            // half of it: the new one has to be refitted to the same screen.
            #expect(await bench.stageFit() == "fitted")
        }
    }

#endif
