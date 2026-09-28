//
//  ViewerChromeBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The chrome's three claims that only a real browser can settle: a hint that opens,
    /// a badge that stops lying when the stream dies, and a path that keeps its tail.
    ///
    /// Each is a fact about layout or about a live connection — which end of a string the
    /// ellipsis eats, which label is the visible one, whether a click reveals anything —
    /// and none of them can be read out of the markup.
    @Suite(.serialized, .hangGuard)
    struct ViewerChromeBrowserTests {
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
            ///   - width: The viewport's width. Narrow squeezes the selection footer,
            ///     which is the only way to see how a long path is truncated.
            ///   - prepare: A chance to write to the file before the server reads it.
            init(
                width: Int = 1440,
                prepare: ((URL, ActivityLog) async throws -> Void)? = nil
            ) async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy("batch.pen", into: scratch)
                log = ActivityLog(home: scratch)
                if let prepare { try await prepare(file, log) }
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [file], port: 0, log: log)
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: width, height: 900),
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

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        /// The name a designer actually types: an em dash, parentheses, and enough of it
        /// to overflow any footer.
        ///
        /// Every one of those is a *neutral* character to the bidi algorithm, which is
        /// what makes this the fixture that catches a front-truncation done by flipping
        /// the box to `direction: rtl` and hoping.
        private static let longName =
            "Fav Card 2 — Cover Image (Light) — Hover, Pressed, Focused and Disabled States"

        /// Adds a node with ``longName`` under `Cards`, so its path is far too long.
        private static func addLongName(_ file: URL, log: ActivityLog) async throws {
            try await PenFileTransaction.run(
                at: file, identity: "seed", log: log, timeout: ViewerFixtures.lockBudget
            ) { _, recorder in
                try recorder.apply(.insertNode(EditOperation.InsertNode(
                    node: PenNode(
                        id: "Lng01",
                        common: PenNodeCommon(name: longName),
                        kind: .rectangle(PenNode.RectangleData(width: .fixed(40), height: .fixed(20)))
                    ),
                    parentID: "Crd01"
                )))
            }
        }

        @MainActor
        @Test("The key hint opens a popover on click, and closes again")
        func theKeyHintOpensAPopover() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            #expect(await bench.ask("""
            return getComputedStyle(document.getElementById('v-keys')).display;
            """) == "none", "the shortcuts are not on screen until they are asked for")

            _ = await bench.ask("document.querySelector('.v-key-hint').click(); return 'ok';")
            await bench.waitFor(
                "the shortcuts popover to open",
                "return getComputedStyle(document.getElementById('v-keys')).display !== 'none';"
            )
            #expect(await bench.ask("""
            return document.getElementById('v-keys').innerText;
            """).contains("presentation"))
        }

        @MainActor
        @Test("A dropped stream reads disconnected, not an amber live")
        func aDroppedStreamReadsDisconnected() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            await bench.waitFor(
                "the stream to come up",
                "return document.getElementById('v-live').dataset.state === 'live';"
            )
            #expect(await bench.ask("return document.getElementById('v-live').innerText.trim();")
                == ConnectionState.live.label)

            await bench.server.stop()
            await bench.waitFor(
                "the badge to notice the stream is gone",
                "return document.getElementById('v-live').dataset.state === 'lost';"
            )
            #expect(await bench.ask("return document.getElementById('v-live').innerText.trim();")
                == ConnectionState.lost.label)
            #expect(ConnectionState.lost.label == "disconnected")
        }

        @MainActor
        @Test("A long selection path keeps its tail and loses its head")
        func aLongSelectionPathIsFrontTruncated() async throws {
            // A full-width window, not a narrow one: below about 700 px the three panes
            // are already wider than the viewport and the canvas column collapses, which
            // would make this a test of a broken layout rather than of truncation.
            let bench = try await Bench(prepare: Self.addLongName)
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Lng01")
            )
            #expect(await bench.ask("""
            return document.getElementById('v-selection-path').textContent.trim();
            """) == "Canvas/Cards/\(Self.longName)")

            // Four facts, reported together so a failure names which one broke: the box
            // really is too small, the *end* of the path is the part still on screen,
            // the beginning is what fell off, and the characters are still in the order
            // they were written — the trap of truncating by flipping the box to RTL is
            // that "(Light)" comes back mirrored and at the wrong end.
            let report = await bench.ask("""
            const el = document.getElementById('v-selection-path');
            const text = document.createTreeWalker(el, NodeFilter.SHOW_TEXT).nextNode();
            const box = el.getBoundingClientRect();
            const range = document.createRange();
            const at = (index) => {
              range.setStart(text, index);
              range.setEnd(text, index + 1);
              return range.getBoundingClientRect();
            };
            const last = text.length - 1;
            const tail = at(last), penult = at(last - 1), head = at(0);
            const problems = [];
            if (el.scrollWidth <= el.clientWidth + 1) problems.push('the path is not overflowing at all');
            if (!(tail.width > 0 && tail.right <= box.right + 1 && tail.left >= box.left - 1)) {
              problems.push('the tail is not the part still drawn');
            }
            // A character the ellipsis ate has a *zero-width* rect at the clip edge —
            // that, not a position off to the left, is how WebKit reports "not drawn".
            if (head.width > 0) problems.push('the head was not the part truncated');
            if (tail.left <= penult.left) problems.push('the characters came back reordered');
            const sizes = `box ${Math.round(box.left)}..${Math.round(box.right)}`
              + ` head ${Math.round(head.left)}..${Math.round(head.right)}`
              + ` tail ${Math.round(tail.left)}..${Math.round(tail.right)}`
              + ` dir ${getComputedStyle(el).direction} scroll ${Math.round(el.scrollWidth)}`;
            return problems.length ? `${problems.join('; ')} (${sizes})` : 'front-truncated';
            """)
            #expect(report == "front-truncated")
        }

        @MainActor
        @Test("The overlay's selection tag stays inside the render pane and keeps the path's tail")
        func theOverlayTagStaysInsideThePane() async throws {
            let bench = try await Bench(prepare: Self.addLongName)
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Lng01")
            )
            // Four facts in one report, so a failure names which one broke: the tag ends
            // inside the pane, its text really is too long for it, the tail character is
            // the one still drawn, and the head is what the ellipsis ate (a clipped
            // character reports a zero-width rect, per the truncation gotcha).
            let report = await bench.ask("""
            const tag = document.querySelector('.v-box.is-selected .v-box-tag');
            if (!tag) return 'no selection tag on the page';
            const pane = document.querySelector('.v-render-scroll').getBoundingClientRect();
            const box = tag.getBoundingClientRect();
            const text = document.createTreeWalker(tag, NodeFilter.SHOW_TEXT).nextNode();
            const range = document.createRange();
            const at = (index) => {
              range.setStart(text, index);
              range.setEnd(text, index + 1);
              return range.getBoundingClientRect();
            };
            const head = at(0), tail = at(text.length - 1);
            const problems = [];
            if (box.right > pane.right + 1) problems.push('the tag escapes the pane');
            // The truncation lives on the flex item inside the tag, so that is where the
            // overflow shows; the tag itself fits by construction.
            const path = tag.querySelector('.v-box-path');
            if (!path) return 'no truncating path wrapper in the tag';
            if (path.scrollWidth <= path.clientWidth + 1) problems.push('the path is not overflowing at all');
            if (!(tail.width > 0)) problems.push('the tail is not the part still drawn');
            if (head.width > 0) problems.push('the head was not the part truncated');
            const sizes = `pane ..${Math.round(pane.right)} tag ${Math.round(box.left)}..${Math.round(box.right)}`
              + ` head ${Math.round(head.width)} tail ${Math.round(tail.width)}`;
            return problems.length ? `${problems.join('; ')} (${sizes})` : 'contained';
            """)
            #expect(report == "contained")
        }

        @MainActor
        @Test("The selection footer fits its pane, copy button and steps included")
        func theFooterFitsItsPane() async throws {
            // Narrower than the shot bench, so the fixed items genuinely contend with the
            // path for room — but comfortably above the ~700px where the three-pane
            // layout itself collapses (see the truncation gotcha).
            let bench = try await Bench(width: 1000, prepare: Self.addLongName)
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Cnv01?node=Lng01")
            )
            let report = await bench.ask("""
            const footer = document.getElementById('v-selection');
            const box = footer.getBoundingClientRect();
            const pane = document.getElementById('v-canvas-body').getBoundingClientRect();
            const problems = [];
            if (footer.scrollWidth > footer.clientWidth + 1) {
              problems.push('the footer scrolls its own content out of view');
            }
            if (box.right > pane.right + 1 || box.width > pane.width + 1) {
              problems.push('the footer is wider than its pane');
            }
            // The last things in the row are the copy button and the steps, and they are
            // the ones an overflow pushes out — both must end inside the footer's box.
            for (const selector of ['.v-copy', '.v-steps, .v-step-next']) {
              const el = footer.querySelector(selector);
              if (!el) { problems.push(`${selector} is missing from the footer`); continue; }
              const rect = el.getBoundingClientRect();
              if (rect.width === 0 || rect.right > box.right + 1) {
                problems.push(`${selector} is pushed out of the pane`);
              }
            }
            const sizes = `pane ..${Math.round(pane.right)} footer ${Math.round(box.left)}..${Math.round(box.right)}`
              + ` scroll ${Math.round(footer.scrollWidth)} client ${Math.round(footer.clientWidth)}`;
            return problems.length ? `${problems.join('; ')} (${sizes})` : 'fits';
            """)
            #expect(report == "fits")
        }
    }

#endif
