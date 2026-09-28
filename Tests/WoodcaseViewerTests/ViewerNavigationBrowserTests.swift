//
//  ViewerNavigationBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// Moving around the viewer without the document being replaced.
    ///
    /// Every test here turns on the same question — *did the page reload?* — and answers
    /// it the only way a browser can be asked honestly: it writes a marker onto `window`
    /// that a navigation would wipe, then checks the marker is still there after the
    /// thing that used to navigate. A test that watched `location` alone would pass just
    /// as well against a full load, which is the bug this leaf exists to fix.
    ///
    /// Its own suite, like ``ViewerSelectionBrowserTests``: a headless page plus a live
    /// server is heavy enough that two suites sharing one bench contend.
    @Suite(.serialized, .hangGuard)
    struct ViewerNavigationBrowserTests {
        /// A server and a page pointed at it.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            /// - Parameters:
            ///   - fixture: The .pen file to serve. `batch.pen` has three artboards, so
            ///     there is somewhere to step to.
            ///   - prepare: A chance to write to the file before the server reads it.
            init(
                _ fixture: String = "batch.pen",
                prepare: ((URL, ActivityLog) async throws -> Void)? = nil
            ) async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy(fixture, into: scratch)
                log = ActivityLog(home: scratch)
                if let prepare { try await prepare(file, log) }
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

            /// Stamps a value onto `window` that only a document replacement can remove.
            ///
            /// A `pushState` keeps the same `window`; a navigation builds a new one. So
            /// this surviving *is* "the page did not reload", and it is the one fact the
            /// URL cannot tell you.
            func markPage() async {
                _ = await ask("window.__woodcaseNavProbe = 'kept'; return 'ok';")
            }

            /// Whether the marker written by ``markPage()`` is still there.
            func pageWasKept() async -> String {
                await ask("return window.__woodcaseNavProbe ?? 'gone';")
            }

            func pressKey(_ key: String) async {
                _ = await ask("""
                document.dispatchEvent(new KeyboardEvent('keydown', { key: '\(key)', bubbles: true, cancelable: true }));
                return 'ok';
                """)
            }

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        /// Appends enough rows to `Cnv01` that the outline panel has to scroll.
        ///
        /// The same shape ``ViewerBrowserTests`` uses for its reveal test: the outline's
        /// scroll position is only a fact worth keeping when there is one.
        private static func padOutline(_ file: URL, log: ActivityLog) async throws {
            try await PenFileTransaction.run(
                at: file, identity: "seed", log: log, timeout: ViewerFixtures.lockBudget
            ) { _, recorder in
                for index in 0 ..< 60 {
                    try recorder.apply(.insertNode(EditOperation.InsertNode(
                        node: PenNode(
                            id: String(format: "Pad%02d", index),
                            common: PenNodeCommon(name: "Pad \(index)"),
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
                        ),
                        parentID: "Cnv01"
                    )))
                }
            }
        }

        // MARK: - Stepping between artboards

        @MainActor
        @Test("An arrow key steps to the next artboard without replacing the document")
        func arrowKeyStepsArtboardsInPlace() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            await bench.markPage()

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the second artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )

            #expect(await bench.pageWasKept() == "kept")
            #expect(await bench.ask("return location.pathname;")
                == "/files/\(bench.fileID)/artboards/Brd01")
        }

        @MainActor
        @Test("An in-place step brings the whole page with it: crumb, title, footer and right pane")
        func steppingSwapsEverythingTheArtboardOwns() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            #expect(await bench.ask("return document.querySelector('.v-crumb.is-current').textContent;") == "Canvas")
            await bench.markPage()

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the second artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            #expect(await bench.pageWasKept() == "kept")

            // The breadcrumb and the tab title name the artboard, and both are server
            // strings — a stale one is the tell that a swap covered the render alone.
            await bench.waitFor(
                "the breadcrumb to name the new artboard",
                "return document.querySelector('.v-crumb.is-current')?.textContent === 'Board';"
            )
            #expect(await bench.ask("return document.title;").hasSuffix("· Board"))
            // The footer's counter, and the right pane's tabs, both moved with it.
            #expect(await bench.ask("return document.querySelector('.v-step-count').textContent;") == "2 of 3")
            #expect(await bench.ask(
                "return document.querySelector('#v-right .v-tab[data-tab=\"export\"]').getAttribute('href');"
            ).contains("/artboards/Brd01"))
            // And the outline's rows now select into the artboard on screen.
            #expect(await bench.ask(
                "return document.querySelector('#v-outline .v-outline-row[data-node=\"Chi01\"]').getAttribute('href');"
            ).contains("/artboards/Brd01"))
        }

        @MainActor
        @Test("Clicking the footer's step link switches in place too")
        func clickingAStepLinkSwitchesInPlace() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Brd01"))
            await bench.markPage()

            _ = await bench.ask("document.querySelector('a.v-step-next').click(); return 'ok';")
            await bench.waitFor(
                "the last artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Cmp01';"
            )
            #expect(await bench.pageWasKept() == "kept")

            // Back is the same mechanism, so a step never becomes a reload one way round.
            _ = await bench.ask("document.querySelector('a.v-step-previous').click(); return 'ok';")
            await bench.waitFor(
                "the middle artboard to be showing again",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            #expect(await bench.pageWasKept() == "kept")
        }

        @MainActor
        @Test("Going back after an in-place step brings the whole first artboard back")
        func historyStepsBackToThePreviousArtboard() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            await bench.markPage()

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the second artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            // The step itself has to have been in place, or what `history.back()` does
            // below is a trip through the back/forward cache rather than a `popstate` —
            // and that cache restores the document so completely that no marker can tell
            // the two apart afterwards. Asserting it here is what keeps the rest honest.
            #expect(await bench.pageWasKept() == "kept")

            _ = await bench.ask("history.back(); return 'ok';")
            await bench.waitFor(
                "the first artboard to come back",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Cnv01';"
            )
            // `popstate` has to bring the same pieces back that the step took forward.
            #expect(await bench.ask("return document.querySelector('.v-crumb.is-current').textContent;") == "Canvas")
            #expect(await bench.ask("return document.querySelector('.v-step-count').textContent;") == "1 of 3")
        }

        @MainActor
        @Test("A step out of presentation mode stays in presentation mode")
        func steppingKeepsPresentationMode() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )
            await bench.markPage()

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the second artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            // Presentation is a class on `<body>`, which only a document replacement can
            // clear — this is the whole reason the switch has to be in place.
            #expect(await bench.ask("return document.body.classList.contains('is-presenting');") == "true")
            #expect(await bench.pageWasKept() == "kept")
        }

        // MARK: - The outline keeps its place

        @MainActor
        @Test("Clicking an outline row selects in place and leaves the panel scrolled where it was")
        func outlineClickKeepsTheScrollPosition() async throws {
            let bench = try await Bench(prepare: { file, log in try await Self.padOutline(file, log: log) })
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            #expect(await bench.ask("""
            const panel = document.getElementById('v-outline');
            return String(panel.scrollHeight > panel.clientHeight);
            """) == "true", "the outline has to overflow for this test to mean anything")
            await bench.markPage()

            // Scroll well down the panel, then click a row that is already in view: the
            // panel has no reason to move, and moving is exactly what the swap did.
            let before = await bench.ask("""
            const panel = document.getElementById('v-outline');
            panel.scrollTop = Math.round((panel.scrollHeight - panel.clientHeight) / 2);
            const rows = Array.from(panel.querySelectorAll('.v-outline-row'));
            const frame = panel.getBoundingClientRect();
            const visible = rows.find((row) => {
              const box = row.getBoundingClientRect();
              return box.top >= frame.top + 8 && box.bottom <= frame.bottom - 8;
            });
            if (!visible) return 'no row is fully in view';
            window.__woodcaseTarget = visible.dataset.node;
            return String(panel.scrollTop);
            """)
            #expect(Double(before) ?? 0 > 0, "expected the outline to be scrolled: \(before)")

            _ = await bench.ask("""
            document.querySelector(`#v-outline .v-outline-row[data-node="${window.__woodcaseTarget}"]`).click();
            return 'ok';
            """)
            await bench.waitFor(
                "the clicked row to come back selected",
                """
                return document.querySelector('#v-outline .v-outline-row.is-selected')?.dataset.node
                  === window.__woodcaseTarget;
                """
            )
            #expect(await bench.pageWasKept() == "kept")

            // The swap replaces the scroll container, so keeping the position is the
            // script's job; a reset shows up here as a jump to the top.
            let after = await bench.ask("return String(document.getElementById('v-outline').scrollTop);")
            let drift = abs((Double(after) ?? 0) - (Double(before) ?? 0))
            #expect(drift < 4, "the outline jumped from \(before) to \(after)")
        }

        // MARK: - Clearing the selection

        @MainActor
        @Test("Clicking the canvas outside the artboard clears the selection, in place")
        func clickingOutsideTheArtboardClearsTheSelection() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Ttl01"))
            #expect(await bench.ask(
                "return !!document.querySelector('#v-outline .v-outline-row.is-selected');"
            ) == "true")
            await bench.markPage()

            // A real point in the canvas pane that is outside the stage — whichever
            // element is actually painted there is the one that gets the click, so this
            // cannot pass by hitting something the test picked by name.
            #expect(await bench.ask("""
            const stage = document.getElementById('v-stage').getBoundingClientRect();
            const pane = document.getElementById('v-canvas-body').getBoundingClientRect();
            const x = Math.round((pane.left + stage.left) / 2);
            const y = Math.round(stage.top + stage.height / 2);
            if (x >= stage.left) return 'the stage fills the pane; no outside to click';
            const target = document.elementFromPoint(x, y);
            if (!target || target.closest('#v-stage')) return 'the point lands on the stage';
            target.dispatchEvent(new MouseEvent('click', {
              bubbles: true, button: 0, clientX: x, clientY: y,
            }));
            return 'ok';
            """) == "ok")

            await bench.waitFor(
                "the selection to clear",
                "return !new URL(location.href).searchParams.get('node');"
            )
            await bench.waitFor(
                "the outline to show nothing selected",
                "return !document.querySelector('#v-outline .v-outline-row.is-selected');"
            )
            #expect(await bench.pageWasKept() == "kept")
        }

        @MainActor
        @Test("Clicking the selection footer is not clicking outside the artboard")
        func clickingTheFooterKeepsTheSelection() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Ttl01"))

            _ = await bench.ask("""
            document.getElementById('v-selection').dispatchEvent(
              new MouseEvent('click', { bubbles: true, button: 0 })
            );
            return 'ok';
            """)
            try await Task.sleep(for: .milliseconds(400))
            #expect(await bench.ask("return new URL(location.href).searchParams.get('node');") == "Ttl01")
        }
    }

#endif
