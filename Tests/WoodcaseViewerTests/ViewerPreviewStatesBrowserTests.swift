//
//  ViewerPreviewStatesBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// What a review shot of a preview state actually shows, measured in a real browser.
    ///
    /// Each case is one finding of the 2026-09-02 catalog review, pinned at the level a
    /// shot sees it: a computed style, a laid-out rect, a loaded image, the attribute the
    /// server wrote still being there after the script ran. Markup tests cannot see any
    /// of these — the markup was right in most of them and the page was not.
    ///
    /// The bench is `woodcase preview`'s shape (no files, no log) at the review loop's own
    /// window, 1280×800, because the frames are measured against that window.
    ///
    /// Serialized, one bench per case, for the reason ``ViewerPreviewBrowserTests`` gives.
    @Suite(.serialized, .hangGuard)
    struct ViewerPreviewStatesBrowserTests {
        @MainActor
        private struct Bench {
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            init(theme: ColorTheme = .light) async throws {
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [], port: 0, logs: [])
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1280, height: 800),
                    theme: theme,
                    wait: .load,
                    budget: 20
                ))
            }

            /// Loads one state's own page.
            func open(_ component: String, _ state: String) async throws {
                _ = try await host.boundedLoad(
                    URL(string: "http://localhost:\(port)\(ViewerLink.previewState(component: component, state: state))")!
                )
            }

            /// Runs a JavaScript body in the page's own world and returns its answer.
            func ask(_ body: String) async -> String {
                guard let json = try? await host.boundedEvaluate(body, in: .page) else { return "" }
                guard let decoded = try? JSONSerialization.jsonObject(
                    with: Data(json.utf8), options: [.fragmentsAllowed]
                ) as? String else { return json }
                return decoded
            }

            func waitFor(_ description: Comment, _ body: String, within bound: Duration = .seconds(30)) async {
                let deadline = ContinuousClock.now + bound
                while ContinuousClock.now < deadline {
                    if await ask(body) == "true" { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                Issue.record("timed out waiting for \(description)")
            }

            func stop() async {
                await server.stop()
            }
        }

        /// WCAG contrast of an element's text against its own background, both computed.
        private static let contrastScript = """
        const parse = (value) => (value.match(/[\\d.]+/g) || []).slice(0, 3).map(Number);
        const channel = (c) => {
          const s = c / 255;
          return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
        };
        const luminance = (rgb) => 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2]);
        const style = getComputedStyle(element);
        const a = luminance(parse(style.color));
        const b = luminance(parse(style.backgroundColor));
        return ((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)).toFixed(2);
        """

        // MARK: - the script leaves the server's picture alone

        @MainActor
        @Test("The unread dot the server wrote on the map crumb survives the script (wNhNQp)")
        func unreadCrumbSurvivesTheScript() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("top-bar", "unread")
            #expect(await bench.ask("return document.documentElement.dataset.js;") == "on")
            #expect(await bench.ask(
                "return document.querySelector('.v-crumb-map').dataset.unread ?? 'none';"
            ) == "1")
        }

        @MainActor
        @Test("The unread dot the server wrote on an artboard row survives the script (wNhNQp)")
        func unreadRowSurvivesTheScript() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-row", "unread")
            #expect(await bench.ask("return document.documentElement.dataset.js;") == "on")
            #expect(await bench.ask(
                "return document.querySelector('[data-artboard]').dataset.unread ?? 'none';"
            ) == "1")
        }

        @MainActor
        @Test("A page preview keeps the presence and badge it declared: no live stream repaints it (GqUQys)")
        func pagePreviewIsNotRepaintedByTheStream() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-page", "default")
            #expect(await bench.ask("return document.documentElement.dataset.stream ?? 'unset';") == "off")
            // The stream used to land within a few hundred milliseconds and swap the
            // fixture's presence for the empty server's. Two seconds of it not happening,
            // checked the whole way, is the regression; the flag above is the cause.
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                let note = await bench.ask("return document.querySelector('.v-presence-note').textContent;")
                #expect(note.contains("2 active"), "presence was repainted to \(note)")
                if !note.contains("2 active") { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            #expect(await bench.ask("return document.getElementById('v-live').dataset.state;") == "connecting")
        }

        @MainActor
        @Test("The artboard render in a preview is a loaded image, not a broken one (4FmPKE)")
        func renderIsALoadedImage() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-overlay", "default")
            await bench.waitFor(
                "the render to finish loading",
                "return String(document.getElementById('v-render').complete);"
            )
            #expect(await bench.ask(
                "return String(document.getElementById('v-render').naturalWidth > 0);"
            ) == "true")
        }

        // MARK: - frames

        @MainActor
        @Test("A bare top-bar control is framed on the chrome it lives on (gtuww7)")
        func topBarFramePaintsChrome() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("theme-picker", "default")
            #expect(await bench.ask(
                "return getComputedStyle(document.querySelector('.v-preview-frame')).backgroundColor;"
            ) == "rgb(236, 234, 227)")
        }

        @MainActor
        @Test("The selection bar is framed on the render column, where a long path truncates (4GVELx)")
        func selectionBarTruncatesInItsColumn() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("selection-bar", "long-path")
            #expect(await bench.ask(
                "return document.querySelector('.v-preview-frame').dataset.frame;"
            ) == "canvas")
            #expect(await bench.ask("""
            const path = document.querySelector('.v-selection-path');
            return String(path.scrollWidth > path.clientWidth);
            """) == "true")
        }

        @MainActor
        @Test("The keyboard hint's panel is drawn in its preview, so its table can be read (2DwWCD)")
        func keyboardPanelIsVisible() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("keyboard-hint", "default")
            #expect(await bench.ask("""
            const panel = document.querySelector('.v-preview-frame .v-key-hint-popover');
            return String(panel.getBoundingClientRect().height > 40);
            """) == "true")
        }

        @MainActor
        @Test("The presentation hint is drawn in its preview, outside the mode that shows it (1sewyf)")
        func presentationHintIsVisible() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("presentation-hint", "default")
            #expect(await bench.ask("""
            const hint = document.querySelector('.v-preview-frame .v-present-hint');
            const box = hint.getBoundingClientRect();
            return String(box.height > 0 && getComputedStyle(hint).opacity === '1');
            """) == "true")
        }

        @MainActor
        @Test("The map's component definition is big enough to keep its name and mark (8fo7Gf)")
        func mapDefinitionKeepsItsLabel() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-map", "default")
            #expect(await bench.ask("""
            const label = document.querySelector('.v-kind-component').closest('.v-map-label');
            const name = label.querySelector('.v-map-name').getBoundingClientRect();
            const mark = label.querySelector('.v-kind-component').getBoundingClientRect();
            return String(name.width > 0 && mark.width > 0);
            """) == "true")
        }

        @MainActor
        @Test("A file card is framed at the dashboard grid's width, not the render column's (KKPpCv)")
        func fileCardSitsInTheDashboardGrid() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("file-card", "default")
            #expect(await bench.ask(
                "return document.querySelector('.v-preview-frame').dataset.frame;"
            ) == "body")
            #expect(await bench.ask(
                "return String(document.querySelector('.v-file-card').getBoundingClientRect().width < 400);"
            ) == "true")
        }

        // MARK: - production layout

        @MainActor
        @Test("A variable row's summary spans the row, so numbers can sit at its right edge (NMfyci)")
        func variableSummarySpansTheRow() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("variables-panel", "default")
            #expect(await bench.ask("""
            const number = document.querySelector('.v-variable-number');
            const row = number.closest('.v-variable-row').getBoundingClientRect();
            const summary = number.closest('.v-variable-summary').getBoundingClientRect();
            return String(Math.abs(row.width - summary.width) < 1);
            """) == "true")
        }

        @MainActor
        @Test("A non-color variable's swatch slot keeps its width but draws nothing (ZIaKPF)")
        func emptySwatchDrawsNothing() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("variables-panel", "default")
            #expect(await bench.ask("""
            const empties = [...document.querySelectorAll('.v-swatch.is-empty')];
            return String(empties.length > 0
              && empties.every((e) => getComputedStyle(e).visibility === 'hidden'));
            """) == "true")
        }

        @MainActor
        @Test("The export form's three controls share one left edge (7ga8KN)")
        func exportControlsLineUp() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("export-panel", "default")
            #expect(await bench.ask("""
            const lefts = ['.v-export-format', '.v-export-scale', '.v-export-max']
              .map((s) => document.querySelector(s).getBoundingClientRect().left);
            return String(Math.max(...lefts) - Math.min(...lefts) < 1);
            """) == "true")
        }

        @MainActor
        @Test("An activity row keeps the tail of its path — the node and the +3 — and loses the head (eJcZJU)")
        func activityPathTruncatesFromTheFront() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("activity-row", "cross-file")
            // A character the ellipsis ate reports a zero-width rect (gotchas.md).
            #expect(await bench.ask("""
            const path = document.querySelector('.v-activity-path');
            const text = path.querySelector('bdi').firstChild;
            const width = (at) => {
              const range = document.createRange();
              range.setStart(text, at); range.setEnd(text, at + 1);
              return range.getBoundingClientRect().width;
            };
            const overflows = path.scrollWidth > path.clientWidth;
            return String(overflows && width(text.length - 1) > 0 && width(0) === 0);
            """) == "true")
        }

        @MainActor
        @Test(
            "An artboard row sheds its rect before it truncates the name (lg6hBh)",
            arguments: ["touched", "unnamed-instance"]
        )
        func artboardRowKeepsItsName(state: String) async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-row", state)
            #expect(await bench.ask("""
            const name = document.querySelector('.v-artboard-row .v-outline-name');
            return String(name.scrollWidth <= name.clientWidth);
            """) == "true")
        }

        @MainActor
        @Test("An edit tag keeps its verb and age inside its own colored ground (vHmA5e)")
        func editTagHoldsItsWords() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-overlay", "default")
            #expect(await bench.ask("""
            const tag = document.querySelector('.v-edit-tag').getBoundingClientRect();
            const op = document.querySelector('.v-edit-op').getBoundingClientRect();
            return String(op.width > 0 && op.right <= tag.right + 0.5);
            """) == "true")
        }

        @MainActor
        @Test(
            "Persistent text on the accent fill reaches AA in both schemes (wRxjaB)",
            arguments: [ColorTheme.light, ColorTheme.dark]
        )
        func persistentAccentTextReachesAA(theme: ColorTheme) async throws {
            let bench = try await Bench(theme: theme)
            defer { Task { await bench.stop() } }

            try await bench.open("variables-panel", "default")
            let pill = await bench.ask(
                "const element = document.querySelector('.v-bool-pill[data-value=\"true\"]');\n"
                    + Self.contrastScript
            )
            #expect((Double(pill) ?? 0) >= 4.5, "the true pill is \(pill):1")

            try await bench.open("artboard-overlay", "default")
            let tag = await bench.ask(
                "const element = document.querySelector('.v-box.is-selected .v-box-tag');\n"
                    + Self.contrastScript
            )
            #expect((Double(tag) ?? 0) >= 4.5, "the selection tag is \(tag):1")
        }
    }

#endif
