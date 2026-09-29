//
//  ViewerKeyboardBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The keyboard model's acceptance tests: a real browser, driven by synthesized
    /// `KeyboardEvent`s rather than an OS-level keystroke.
    ///
    /// SleepyHollow's own act verbs — `click`, `fill`, `submit` — have no keyboard
    /// counterpart: there is no operation that presses a key. So these tests dispatch a
    /// `KeyboardEvent` through `PageHost.evaluate` instead, exactly as `ClickOperation`
    /// is itself "honest about mechanism" — a synthesized DOM event, not a hardware key
    /// press. `ViewerScript`'s own `keydown` listener cannot tell the difference, which
    /// is what makes this a faithful test of it.
    ///
    /// Every row of `window.__woodcaseKeys` — the same table the script dispatches
    /// from — has a behavioral test below; ``keyTableMatchesTheDocumentedSpec`` pins
    /// the table itself, so a row added or reworded without a matching test here is
    /// caught by that mismatch rather than by silence.
    ///
    /// Serialized, and one bench per test rather than shared with ``ViewerBrowserTests``:
    /// a headless page plus a live server is heavy enough that two independent suites
    /// contend if they share one.
    @Suite(.serialized, .hangGuard)
    struct ViewerKeyboardBrowserTests {
        /// A server and a page pointed at it — the same shape as ``ViewerBrowserTests``'
        /// own bench, kept separate so the two files never touch one another.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            /// - Parameter fixture: The .pen file to serve. `batch.pen` has three
            ///   artboards and so a map to go up to; a single-artboard file has none,
            ///   which is a different rung of Escape's ladder.
            init(fixture: String = "batch.pen") async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy(fixture, into: scratch)
                log = ActivityLog(home: scratch)
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [file], port: 0, log: log)
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1440, height: 900),
                    wait: .load,
                    budget: 20
                ))
            }

            func url(_ path: String) -> URL {
                URL(string: "http://localhost:\(port)\(path)")!
            }

            /// Runs a JavaScript body in the page's own world and returns its answer.
            ///
            /// `PageHost.evaluate` transports the value as JSON text, so a string comes
            /// back inside its quotes; decoding here is what stops every comparison in
            /// this file having to know that.
            func ask(_ body: String) async -> String {
                guard let json = try? await host.boundedEvaluate(body, in: .page) else { return "" }
                guard let decoded = try? JSONSerialization.jsonObject(
                    with: Data(json.utf8), options: [.fragmentsAllowed]
                ) as? String else { return json }
                return decoded
            }

            /// Waits for a JavaScript body to answer `"true"`.
            ///
            /// The bound is generous on purpose: a test that presses an arrow key on the
            /// artboard strip waits out a real page navigation, not a fragment swap.
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

            /// Dispatches a synthesized `keydown` on `document` — the target
            /// `ViewerScript`'s handler listens on.
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

        /// One row of ``ViewerScript``'s key table, decoded from `window.__woodcaseKeys`.
        ///
        /// `JSON.stringify` drops a JavaScript function silently, so decoding the page's
        /// own table never sees the `run` closure each row also carries — only the three
        /// fields a test or a person reading the page needs.
        private struct KeyTableRow: Decodable, Equatable {
            let key: String
            let context: String
            let label: String
        }

        @MainActor
        @Test("The key table exposed to the page matches the documented spec")
        func keyTableMatchesTheDocumentedSpec() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            let json = try await bench.host.boundedEvaluate("return window.__woodcaseKeys;", in: .page)
            let rows = try JSONDecoder().decode([KeyTableRow].self, from: Data(json.utf8))

            #expect(rows == [
                KeyTableRow(key: "ArrowLeft", context: "map", label: "previous artboard box"),
                KeyTableRow(key: "ArrowRight", context: "map", label: "next artboard box"),
                KeyTableRow(key: "ArrowUp", context: "map", label: "previous artboard box"),
                KeyTableRow(key: "ArrowDown", context: "map", label: "next artboard box"),
                KeyTableRow(key: "Enter", context: "map", label: "open the artboard on the ring"),
                KeyTableRow(key: "ArrowLeft", context: "none-selected", label: "previous artboard"),
                KeyTableRow(key: "ArrowRight", context: "none-selected", label: "next artboard"),
                KeyTableRow(key: "ArrowUp", context: "selected", label: "previous outline row"),
                KeyTableRow(key: "ArrowDown", context: "selected", label: "next outline row"),
                KeyTableRow(key: "ArrowLeft", context: "selected", label: "collapse the selected row's children"),
                KeyTableRow(key: "ArrowRight", context: "selected", label: "expand the selected row's children"),
                KeyTableRow(key: "f", context: "any", label: "toggle presentation mode"),
                KeyTableRow(
                    key: "Escape", context: "any",
                    label: "leave presentation, else select the parent, else go up to the map"
                ),
            ])
        }

        @MainActor
        @Test("With nothing selected, arrow keys step between artboards like a tab click")
        func arrowKeysStepArtboardsWhenNothingIsSelected() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Cnv01"))
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Cnv01")

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the page to navigate to the second artboard",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "the page to navigate to the last artboard",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Cmp01';"
            )

            // The last artboard: → does nothing rather than wrapping around.
            await bench.pressKey("ArrowRight")
            try await Task.sleep(for: .milliseconds(300))
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Cmp01")

            await bench.pressKey("ArrowLeft")
            await bench.waitFor(
                "the page to navigate back a step",
                "return document.getElementById('v-stage')?.dataset.artboard === 'Brd01';"
            )
        }

        @MainActor
        @Test("With a node selected, arrow keys step to the previous or next outline row")
        func arrowKeysStepOutlineRowsWhenSelected() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)?node=Ttl01"))
            #expect(await bench.ask("return location.search;") == "?node=Ttl01")

            // Waited on the DOM's own `is-selected` row, not `location.search`: `go()`
            // pushes the new URL before its fragment swap lands, so a check against the
            // URL alone can read "moved" a beat before the outline actually has. This is
            // an expression, not a statement, so it can be wrapped in another `return`.
            let selectedNode = "document.querySelector('#v-outline .v-outline-row.is-selected')?.dataset.node"

            // Document order, scoped to Cnv01's own tree: Cnv01, Ttl01, Crd01, Cd101, Cd201.
            // The sibling artboard `Brd01` and the component `Cmp01` sit outside it and
            // never appear here — that is the outline's whole point.
            await bench.pressKey("ArrowDown")
            await bench.waitFor(
                "the selection to move to the next outline row",
                "return (\(selectedNode)) === 'Crd01';"
            )

            await bench.pressKey("ArrowUp")
            await bench.waitFor(
                "the selection to move back to the previous outline row",
                "return (\(selectedNode)) === 'Ttl01';"
            )
        }

        @MainActor
        @Test("With a node selected, arrow keys collapse or expand its children; a leaf ignores them")
        func arrowKeysCollapseAndExpandChildren() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)?node=Crd01"))
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Cd101\"]').hidden;"
            ) == "false")

            await bench.pressKey("ArrowLeft")
            await bench.waitFor(
                "Crd01's first child to be hidden",
                "return document.querySelector('.v-outline-row[data-node=\"Cd101\"]').hidden === true;"
            )
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Cd201\"]').hidden;"
            ) == "true")
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Crd01\"]').classList.contains('is-row-collapsed');"
            ) == "true")
            // A sibling outside the collapsed row's subtree is unaffected — Ttl01, not
            // Crd01's own descendant, and no longer another artboard's row entirely
            // now that the outline is scoped to the one on screen.
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').hidden;"
            ) == "false")

            await bench.pressKey("ArrowRight")
            await bench.waitFor(
                "Crd01's children to be visible again",
                "return document.querySelector('.v-outline-row[data-node=\"Cd101\"]').hidden === false;"
            )
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Crd01\"]').classList.contains('is-row-collapsed');"
            ) == "false")

            // A leaf: select it, then ← and → both do nothing.
            _ = await bench.ask("document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').click(); return 'ok';")
            await bench.waitFor(
                "Ttl01 to become selected",
                "return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').classList.contains('is-selected');"
            )

            await bench.pressKey("ArrowRight")
            await bench.pressKey("ArrowLeft")
            try await Task.sleep(for: .milliseconds(300))
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').classList.contains('is-row-collapsed');"
            ) == "false")
            #expect(await bench.ask("return location.search;") == "?node=Ttl01&tab=details")
        }

        @MainActor
        @Test("'f' toggles a presentation mode that hides chrome but keeps the selection")
        func presentationTogglesChromeAndKeepsSelection() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)?node=Ttl01"))
            #expect(await bench.ask("return document.body.classList.contains('is-presenting');") == "false")
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-topbar')).display;") != "none")

            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-topbar')).display;") == "none")
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-side')).display;") == "none")
            #expect(await bench.ask("return getComputedStyle(document.getElementById('v-overlay')).display;") == "none")
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-render')).display;") != "none")
            // The selection is kept — just not drawn while presenting.
            #expect(await bench.ask("return location.search;") == "?node=Ttl01")

            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to disengage",
                "return document.body.classList.contains('is-presenting') === false;"
            )
            #expect(await bench.ask("return getComputedStyle(document.querySelector('.v-topbar')).display;") != "none")
        }

        @MainActor
        @Test("Escape leaves presentation, then selects the parent, then goes up to the map")
        func escapeLeavesPresentationBeforeGoingUp() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Cnv01?node=Ttl01"))
            await bench.pressKey("f")
            await bench.waitFor(
                "presentation mode to engage",
                "return document.body.classList.contains('is-presenting') === true;"
            )

            await bench.pressKey("Escape")
            await bench.waitFor(
                "presentation mode to disengage",
                "return document.body.classList.contains('is-presenting') === false;"
            )
            // The keystroke that left presentation must not also navigate.
            #expect(await bench.ask("return location.search;") == "?node=Ttl01")

            // The next one climbs to the selection's parent — the artboard root — and
            // stays on the artboard.
            await bench.pressKey("Escape")
            await bench.waitFor("the parent to be selected", "return new URLSearchParams(location.search).get('node') === 'Cnv01';")
            // The URL moves before the outline swap lands; the next keypress reads the
            // DOM, so wait for the row itself or Esc toggles the stale selection.
            await bench.waitFor(
                "the outline to show the parent as selected",
                "return document.querySelector('#v-outline .v-outline-row.is-selected')?.dataset.node === 'Cnv01';"
            )
            #expect(await bench.ask("return location.pathname;") == "/files/\(file)/artboards/Cnv01")

            // From the root, the one after climbs to the map.
            await bench.pressKey("Escape")
            await bench.waitFor(
                "Escape to go up to the map",
                "return !!document.getElementById('v-map');"
            )
            #expect(await bench.ask("return location.pathname;") == "/files/\(file)")
        }

        @MainActor
        @Test("With no map to go up to, Escape climbs to the root and then clears the selection")
        func escapeClearsTheSelectionOnASingleArtboardFile() async throws {
            let bench = try await Bench(fixture: "layout-nested.pen")
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)?node=BzwEx"))
            #expect(await bench.ask("return !!document.querySelector('.v-crumb-map');") == "false")

            // Climb: each press selects the parent until the root, then clears.
            for _ in 0 ..< 6 {
                await bench.pressKey("Escape")
                try? await Task.sleep(for: .milliseconds(300))
                if await bench.ask("return location.search;") == "" { break }
            }
            await bench.waitFor("the selection to clear", "return location.search === '';")
        }

        @MainActor
        @Test("Keys are ignored while focus is in a form control")
        func keysIgnoredInFormControls() async throws {
            let bench = try await Bench()
            let file = ViewerFile(url: bench.file).id
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(file)/artboards/Cnv01"))
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Cnv01")

            #expect(await bench.ask("""
            const probe = document.createElement('input');
            probe.id = '__woodcaseProbe';
            document.body.appendChild(probe);
            probe.focus();
            return document.activeElement === probe ? 'focused' : 'not-focused';
            """) == "focused")

            _ = await bench.ask("""
            document.getElementById('__woodcaseProbe').dispatchEvent(
              new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true })
            );
            return 'ok';
            """)
            try await Task.sleep(for: .milliseconds(300))
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Cnv01")
        }
    }

#endif
