//
//  ViewerBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The leaf's acceptance test: a real browser, a real server, a real edit.
    ///
    /// Everything else in this target proves a component renders what it should. This
    /// proves the *page works*: that an edit made by another process reaches an already
    /// open page without a reload, and that clicking a row in the outline outlines that
    /// node over the render and names it.
    ///
    /// Serialized, and one host for the pair: a headless WebKit page plus a live server
    /// plus a render is heavy, and running two of them beside the rest of the suite is
    /// how a run wedges.
    @Suite(.serialized, .hangGuard)
    struct ViewerBrowserTests {
        /// A server and a page pointed at it.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            /// Copies a fixture, lets a caller edit it, and serves it.
            ///
            /// - Parameters:
            ///   - fixture: The .pen file to copy into the scratch directory.
            ///   - prepare: An edit to make *before* the server starts, for a test that
            ///     needs a shape the corpus does not carry — a long outline, say. Edits
            ///     made after this point are what the page is supposed to notice.
            init(
                fixture: String = "batch.pen",
                prepare: ((URL, ActivityLog) async throws -> Void)? = nil
            ) async throws {
                scratch = try ViewerFixtures.scratch()
                let root = scratch
                file = try ViewerFixtures.copy(fixture, into: root)
                log = ActivityLog(home: root)
                try await prepare?(file, log)
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [file], port: 0, log: log)
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1440, height: 900),
                    wait: .load,
                    budget: 20
                ))
            }

            /// The address to load. `localhost` rather than `127.0.0.1` because App
            /// Transport Security exempts it by name, and a test that fails on ATS reads
            /// exactly like a server that is not listening.
            func url(_ path: String) -> URL {
                URL(string: "http://localhost:\(port)\(path)")!
            }

            /// Runs a JavaScript body in the page's own world and returns its answer.
            ///
            /// `PageHost.evaluate` transports the value as *JSON text*, so a string comes
            /// back inside its quotes. Decoding here is what stops every comparison in
            /// this file having to know that.
            func ask(_ body: String) async -> String {
                guard let json = try? await host.boundedEvaluate(body, in: .page) else { return "" }
                guard let decoded = try? JSONSerialization.jsonObject(
                    with: Data(json.utf8), options: [.fragmentsAllowed]
                ) as? String else { return json }
                return decoded
            }

            /// Waits for a JavaScript body to answer `"true"`.
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

            /// Navigates to `url` and waits for `predicate`, re-issuing the navigation
            /// itself if the page never shows it.
            ///
            /// A defense against a real navigation this host did not track: when a click
            /// (rather than this helper) started the *previous* navigation, SleepyHollow's
            /// `PageHost` can resume this `load` from a late `didFinish` that actually
            /// belongs to that earlier one — it resumes whichever load is pending on the
            /// next callback it gets, with no check that the callback is *this*
            /// navigation's own. `load` then returns claiming success while the page is
            /// still showing whatever it showed before, and no amount of waiting
            /// recovers a step that never landed (`project/gotchas.md`, "A wait after an
            /// irreversible step tests nothing") — so this re-navigates instead of
            /// waiting out the full budget on a page that was never coming.
            func reload(
                _ url: URL,
                until description: Comment,
                _ predicate: String,
                attempts: Int = 3
            ) async throws {
                for attempt in 1 ... attempts {
                    _ = try await host.boundedLoad(url)
                    let deadline = ContinuousClock.now + .seconds(10)
                    while ContinuousClock.now < deadline {
                        if await ask(predicate) == "true" { return }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if attempt == attempts {
                        Issue.record("timed out waiting for \(description) after \(attempts) reloads")
                    }
                }
            }

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        @MainActor
        @Test("A file edit updates the artboard without a reload")
        func editUpdatesWithoutAReload() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(ViewerFile(url: bench.file).id)/artboards/Cnv01")
            )

            // A value on the page's own window: a reload wipes it, a fragment swap does
            // not. This is what makes the assertion *without a reload* rather than
            // merely *eventually correct*.
            _ = await bench.ask("window.__probe = 'kept'; return 'ok';")
            await bench.waitFor(
                "the event stream to connect",
                "return document.getElementById('v-live').dataset.state === 'live';"
            )
            #expect(await bench.ask("return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').textContent;")
                .contains("Title"))

            try await PenFileTransaction.run(at: bench.file, identity: "claude-a", log: bench.log, timeout: ViewerFixtures.lockBudget) { _, recorder in
                try recorder.apply(.updateCommon(EditOperation.UpdateCommon(
                    nodeID: "Ttl01", common: PenNodeCommon(name: "Renamed")
                )))
            }

            await bench.waitFor(
                "the outline to show the new name",
                "return document.getElementById('v-outline').textContent.includes('Renamed');"
            )
            await bench.waitFor(
                "an edit marker attributed to claude-a over the render",
                "return !!document.querySelector('#v-overlay .v-box.is-edit[data-editors=\"claude-a\"]');"
            )

            #expect(await bench.ask("return window.__probe ?? 'gone';") == "kept")
            #expect(await bench.ask("return document.getElementById('v-activity').textContent.includes('claude-a');") == "true")
        }

        @MainActor
        @Test("Selecting a node in the outline shows an outline in the render and its name path")
        func selectingOutlinesTheNode() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(ViewerFile(url: bench.file).id)/artboards/Cnv01")
            )
            _ = await bench.ask("window.__probe = 'kept'; return 'ok';")
            #expect(await bench.ask("return !!document.querySelector('#v-overlay .v-box.is-selected');") == "false")

            _ = await bench.ask("document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').click(); return 'ok';")

            await bench.waitFor(
                "the selected node to be outlined over the render",
                "return !!document.querySelector('#v-overlay .v-box.is-selected[data-node=\"Ttl01\"]');"
            )
            await bench.waitFor(
                "the footer to name the selected node",
                "return (document.getElementById('v-selection-path')?.textContent ?? '').length > 0;"
            )

            let path = await bench.ask("return document.getElementById('v-selection-path').textContent;")
            #expect(path.contains("Title"))
            #expect(await bench.ask("return document.querySelector('.v-copy').dataset.copy;") == path)
            // The selection also moves the right pane to Details, and the URL says so.
            #expect(await bench.ask("return location.search;") == "?node=Ttl01&tab=details")
            #expect(await bench.ask("return window.__probe ?? 'gone';") == "kept")
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').classList.contains('is-selected');"
            ) == "true")
        }

        @MainActor
        @Test("An artboard added while the page is open joins the map without a reload")
        func newArtboardJoinsTheStrip() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            _ = await bench.ask("window.__probe = 'kept'; return 'ok';")
            await bench.waitFor(
                "the event stream to connect",
                "return document.getElementById('v-live').dataset.state === 'live';"
            )
            #expect(await bench.ask(
                "return String(document.querySelectorAll('#v-map .v-map-board').length);"
            ) == "3")
            #expect(await bench.ask(
                "return String(document.querySelectorAll('#v-outline .v-artboard-row').length);"
            ) == "3", "the listing beside the map is the same list")

            try await PenFileTransaction.run(
                at: bench.file, identity: "claude-b", log: bench.log, timeout: ViewerFixtures.lockBudget
            ) { _, recorder in
                try recorder.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
                    id: "Lat01",
                    common: PenNodeCommon(name: "Late", x: .literal(0), y: .literal(700)),
                    kind: .frame(PenNode.FrameData(width: .fixed(300), height: .fixed(120)))
                ))))
            }

            await bench.waitFor(
                "the map to carry a box for the artboard that was just added",
                """
                const box = document.querySelector('#v-map .v-map-board[data-artboard="Lat01"]');
                return String(box?.style.getPropertyValue('--v-board-y').trim() === '700');
                """
            )
            await bench.waitFor(
                "the listing beside it to grow the same row",
                "return !!document.querySelector('#v-outline .v-artboard-row[data-artboard=\"Lat01\"]');"
            )
            #expect(await bench.ask("return window.__probe ?? 'gone';") == "kept")
        }

        @MainActor
        @Test("A file with more than one artboard lands on the map; one artboard lands on it")
        func landingDependsOnHowManyArtboardsThereAre() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            #expect(await bench.ask("return !!document.getElementById('v-map');") == "true")
            #expect(await bench.ask("return !!document.getElementById('v-stage');") == "false")

            // Every box is a real render that the browser actually decoded — an <img>
            // that 404s is `complete` too, so `naturalWidth` is what proves it loaded.
            await bench.waitFor(
                "all three thumbnails to load",
                """
                const thumbs = [...document.querySelectorAll('#v-map .v-map-thumb')];
                return String(thumbs.length === 3
                    && thumbs.every((image) => image.complete && image.naturalWidth > 0));
                """
            )

            let single = try await Bench(fixture: "layout-nested.pen")
            defer { Task { await single.stop() } }
            _ = try await bench.host.boundedLoad(single.url("/files/\(ViewerFile(url: single.file).id)"))
            #expect(await bench.ask("return !!document.getElementById('v-stage');") == "true")
            #expect(await bench.ask("return !!document.getElementById('v-map');") == "false")
            #expect(await bench.ask("return !!document.querySelector('.v-crumb-map');") == "false",
                    "with nowhere to go up to, the file crumb is not a map link")
        }

        @MainActor
        @Test("The breadcrumb goes back up to the map, and Escape does the same")
        func theBreadcrumbAndEscapeGoBackUp() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Brd01"))
            #expect(await bench.ask(
                "return document.querySelector('.v-crumb-map').getAttribute('href');"
            ) == "/files/\(file)")

            _ = await bench.ask("document.querySelector('.v-crumb-map').click(); return 'ok';")
            await bench.waitFor(
                "the map to come back",
                "return !!document.getElementById('v-map');"
            )
            #expect(await bench.ask("return location.pathname;") == "/files/\(file)")

            // And from an artboard with nothing selected, Escape climbs the same step.
            //
            // `reload`, not a bare `host.load` + `waitFor`: the click above started a
            // real, untracked navigation (the map and an artboard are "two different
            // pages", so it falls through to the browser rather than being intercepted),
            // and a `load` right after it can settle early on that navigation's own,
            // late completion — see ``Bench/reload(_:until:_:attempts:)``. Escape's
            // handler reads `.v-crumb-map`, which only exists on an artboard page:
            // dispatched while the map from the click is still showing, it is a no-op a
            // plain wait could never recover from.
            try await bench.reload(
                bench.url("/files/\(file)/artboards/Brd01"),
                until: "the reloaded artboard page to be showing before Escape is dispatched",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            _ = await bench.ask("""
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
            return 'ok';
            """)
            await bench.waitFor(
                "Escape to go up to the map",
                "return !!document.getElementById('v-map');"
            )
        }

        @MainActor
        @Test("The footer steps to the artboard either side, and the arrows click those links")
        func theFooterStepsBetweenArtboards() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Brd01"))
            #expect(await bench.ask(
                "return document.querySelector('.v-step-count').textContent;"
            ) == "2 of 3")

            _ = await bench.ask("document.querySelector('a.v-step-next').click(); return 'ok';")
            await bench.waitFor(
                "the next artboard to be showing",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Cmp01';"
            )
            #expect(await bench.ask(
                "return document.querySelector('.v-step-count').textContent;"
            ) == "3 of 3")
            // The last artboard: no link back forward, so nothing wraps.
            #expect(await bench.ask("return !!document.querySelector('a.v-step-next');") == "false")

            // ← is the same click, which is why the two cannot disagree.
            _ = await bench.ask("""
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }));
            return 'ok';
            """)
            await bench.waitFor(
                "the arrow key to step back",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
        }

        @MainActor
        @Test("On the map, arrows move a ring through the boxes and Enter drills in")
        func theRingWalksTheMapAndEnterDrillsIn() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)"))
            #expect(await bench.ask("return !!document.querySelector('.is-focused');") == "false")

            let press = { (key: String) in
                await bench.ask("""
                document.dispatchEvent(new KeyboardEvent('keydown', { key: '\(key)', bubbles: true, cancelable: true }));
                return 'ok';
                """)
            }

            _ = await press("ArrowRight")
            await bench.waitFor(
                "the ring to land on the first box",
                "return document.querySelector('#v-map .v-map-board.is-focused')?.dataset.artboard === 'Cnv01';"
            )
            // One ring, mirrored: the listing highlights the same artboard.
            #expect(await bench.ask(
                "return document.querySelector('#v-outline .v-artboard-row.is-focused')?.dataset.artboard;"
            ) == "Cnv01")

            _ = await press("ArrowDown")
            await bench.waitFor(
                "↓ to move the ring on, like →",
                "return document.querySelector('#v-map .v-map-board.is-focused')?.dataset.artboard === 'Brd01';"
            )
            _ = await press("ArrowUp")
            await bench.waitFor(
                "↑ to move it back, like ←",
                "return document.querySelector('#v-map .v-map-board.is-focused')?.dataset.artboard === 'Cnv01';"
            )

            _ = await press("ArrowRight")
            _ = await press("Enter")
            await bench.waitFor(
                "Enter to drill into the artboard on the ring",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            #expect(await bench.ask("return location.pathname;") == "/files/\(file)/artboards/Brd01")
            #expect(await bench.ask("return !!document.getElementById('v-map');") == "false",
                    "the artboard view gives the render the whole pane")
        }

        @MainActor
        @Test("A click selects in an artboard that does not sit at the canvas origin")
        func clickingSelectsInAnyArtboard() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            // `Brd01` sits at (500, 40) on the canvas and is still drawn from its own
            // top-left corner, so the middle of its image is (100, 50) in the artboard's
            // own points — which is where the hit test has to look.
            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(ViewerFile(url: bench.file).id)/artboards/Brd01")
            )
            #expect(await bench.ask("return !!document.querySelector('#v-overlay .v-box.is-selected');") == "false")

            _ = await bench.ask("""
            const image = document.querySelector('.v-render');
            const box = image.getBoundingClientRect();
            image.dispatchEvent(new MouseEvent('click', {
              bubbles: true,
              clientX: box.left + box.width / 2,
              clientY: box.top + box.height / 2
            }));
            return 'ok';
            """)

            await bench.waitFor(
                "the node under the click to be selected",
                "return !!document.querySelector('#v-overlay .v-box.is-selected');"
            )
            #expect(await bench.ask("return location.search.startsWith('?node=');") == "true")
            #expect(await bench.ask(
                "return !!document.querySelector('#v-outline .v-outline-row.is-selected');"
            ) == "true")
        }

        @MainActor
        @Test("Clicking a box on the artboard map focuses that artboard")
        func clickingTheMapFocusesAnArtboard() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            let file = ViewerFile(url: bench.file).id
            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)"))

            // `Brd01` sits at (500, 40) on the canvas, so its box is to the right of
            // `Cnv01`'s — the map's whole point, and what makes this click a map click.
            #expect(await bench.ask("""
            const boards = [...document.querySelectorAll('#v-map .v-map-board')];
            const a = boards.find((b) => b.dataset.artboard === 'Cnv01').getBoundingClientRect();
            const b = boards.find((b) => b.dataset.artboard === 'Brd01').getBoundingClientRect();
            return String(b.left > a.left && boards.length === 3);
            """) == "true")

            _ = await bench.ask(
                "document.querySelector('#v-map .v-map-board[data-artboard=\"Brd01\"]').click(); return 'ok';"
            )
            await bench.waitFor(
                "the page to be showing the artboard whose box was clicked",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
            #expect(await bench.ask("return location.pathname;") == "/files/\(file)/artboards/Brd01")
            #expect(await bench.ask("return !!document.querySelector('.v-map-board');") == "false")

            // A row in the listing is the same link, and drills in the same way.
            //
            // `reload`, not a bare `host.load`: the box click above started a real,
            // untracked navigation back from the artboard, and the same race described at
            // ``Bench/reload(_:until:_:attempts:)`` can settle this `load` before the map
            // has actually come back — this row only exists there.
            try await bench.reload(
                bench.url("/files/\(file)"),
                until: "the map to be showing before the outline row is clicked",
                "return !!document.getElementById('v-map');"
            )
            _ = await bench.ask(
                "document.querySelector('#v-outline .v-artboard-row[data-artboard=\"Cmp01\"]').click(); return 'ok';"
            )
            await bench.waitFor(
                "the page to be showing the artboard whose row was clicked",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Cmp01';"
            )
        }

        /// Adds a root 40 000 points to the right of everything else.
        private static func spreadWide(_ file: URL, log: ActivityLog) async throws {
            try await PenFileTransaction.run(
                at: file, identity: "seed", log: log, timeout: ViewerFixtures.lockBudget
            ) { _, recorder in
                try recorder.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
                    id: "Far01",
                    common: PenNodeCommon(name: "Far", x: .literal(40000), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(width: .fixed(300), height: .fixed(120)))
                ))))
            }
        }

        @MainActor
        @Test("A 40 000-point spread holds the minimum zoom and scrolls instead")
        func aWideSpreadScrollsRatherThanShrinking() async throws {
            let bench = try await Bench(prepare: { file, log in try await Self.spreadWide(file, log: log) })
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            await bench.waitFor(
                "the map to settle on the minimum zoom",
                """
                const map = document.getElementById('v-map');
                return String(parseFloat(map.style.getPropertyValue('--v-map-scale'))
                    === \(ArtboardMap.minimumScale));
                """
            )
            #expect(await bench.ask("""
            const map = document.getElementById('v-map');
            const plane = map.querySelector('.v-map-plane');
            return String(plane.getBoundingClientRect().width > map.clientWidth
                && map.scrollWidth > map.clientWidth);
            """) == "true", "the map scrolls rather than shrinking below the minimum zoom")

            // The canvas pane is sized by the pane. A plane 40 000 points wide must not
            // stretch the page: the whole point of the two explicit grid tracks.
            #expect(await bench.ask("""
            const map = document.getElementById('v-map');
            return String(map.clientWidth < 1000
                && document.documentElement.scrollWidth <= window.innerWidth);
            """) == "true", "the canvas is sized by the pane, never by the plane inside it")

            // A 200-point artboard is 12 CSS pixels at that zoom — too small for a
            // label, so its name is left to the box's title.
            #expect(await bench.ask("""
            const box = document.querySelector('#v-map .v-map-board[data-artboard="Brd01"]');
            const label = box.querySelector('.v-map-label');
            return String(box.title === 'Board' && getComputedStyle(label).display === 'none');
            """) == "true")

            // And the box the ring lands on is scrolled into the pane, however far out on
            // the canvas it sits: ← from nowhere takes the last one, 40 000 points right.
            _ = await bench.ask("""
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }));
            return 'ok';
            """)
            await bench.waitFor(
                "the map to scroll the ring into view",
                """
                const map = document.getElementById('v-map');
                const ring = map.querySelector('.v-map-board.is-focused');
                if (!ring || ring.dataset.artboard !== 'Far01') return 'false';
                const box = ring.getBoundingClientRect();
                const frame = map.getBoundingClientRect();
                return String(map.scrollLeft > 0
                    && box.left >= frame.left - 1 && box.right <= frame.right + 1);
                """
            )
        }

        /// Whether the selected outline row is inside the panel's visible box.
        private static let selectedRowIsInView = """
        const panel = document.getElementById('v-outline');
        const row = panel.querySelector('.v-outline-row.is-selected');
        if (!row) return 'no-selected-row';
        const box = panel.getBoundingClientRect();
        const rect = row.getBoundingClientRect();
        return String(rect.top >= box.top - 1 && rect.bottom <= box.bottom + 1);
        """

        /// Appends enough rows to `Cnv01` that the outline panel has to scroll.
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

        @MainActor
        @Test("Selecting a node scrolls the outline to its row")
        func selectionScrollsTheOutlineToItsRow() async throws {
            let bench = try await Bench(prepare: { file, log in try await Self.padOutline(file, log: log) })
            defer { Task { await bench.stop() } }

            let file = ViewerFile(url: bench.file).id
            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Cnv01"))
            #expect(await bench.ask("""
            const panel = document.getElementById('v-outline');
            return String(panel.scrollHeight > panel.clientHeight);
            """) == "true", "the outline has to overflow for this test to mean anything")

            _ = await bench.ask("document.querySelector('.v-outline-row[data-node=\"Pad59\"]').click(); return 'ok';")
            await bench.waitFor(
                "the clicked row to come back selected",
                "return !!document.querySelector('#v-outline .v-outline-row.is-selected[data-node=\"Pad59\"]');"
            )
            #expect(await bench.ask(Self.selectedRowIsInView) == "true")

            // And a page opened straight at a selection, which is the link an agent
            // pastes — the file's own URL, which resolves to the artboard holding it
            // rather than to the map.
            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)?node=Pad59"))
            #expect(await bench.ask("return document.getElementById('v-stage')?.dataset.artboard;") == "Cnv01")
            #expect(await bench.ask(Self.selectedRowIsInView) == "true")
        }
    }

#endif
