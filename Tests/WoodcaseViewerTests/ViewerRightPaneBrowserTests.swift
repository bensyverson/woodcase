//
//  ViewerRightPaneBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The right pane's tabs, the export endpoint and the code split view, driven in a
    /// real browser against a real server.
    ///
    /// Its own suite, like ``ViewerCopyChipBrowserTests``: a headless WebKit page plus a
    /// live server is heavy, and keeping each leaf's bench separate means two of them
    /// never contend over one file.
    @Suite(.serialized, .hangGuard)
    struct ViewerRightPaneBrowserTests {
        /// A server and a page pointed at it.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            init(_ fixture: String) async throws {
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

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        // MARK: - Details

        @MainActor
        @Test("Selecting an overridden node shows the override marked with its source")
        func overrideShowsItsSource() async throws {
            let bench = try await Bench("addressing.pen")
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Dash1"))

            // Activity is the tab a page with no selection opens on.
            #expect(await bench.ask("return document.querySelector('.v-side-right').dataset.tab;") == "activity")

            let row = "document.querySelector('.v-outline-row[data-node=\"Nav01/Lbl01\"]')"
            #expect(await bench.ask("return !!\(row);") == "true")
            _ = await bench.ask("\(row).click(); return 'ok';")

            await bench.waitFor(
                "the right pane to move to Details",
                "return document.querySelector('.v-side-right').dataset.tab === 'details';"
            )
            await bench.waitFor(
                "the overridden property to arrive",
                "return !!document.querySelector('#v-details .v-detail-row[data-path=\"kind.content\"]');"
            )

            let detail = "document.querySelector('#v-details .v-detail-row[data-path=\"kind.content\"]')"
            #expect(await bench.ask("return \(detail).dataset.origin;") == "override")
            #expect(await bench.ask("return \(detail).dataset.instance;") == "Nav01")
            #expect(await bench.ask(
                "return \(detail).querySelector('.v-detail-source').textContent;"
            ).contains("Dashboard/Body/Nav"))
            #expect(await bench.ask(
                "return \(detail).querySelector('.v-detail-value').textContent;"
            ) == "Menu")

            // Clearing the selection puts Activity back.
            _ = await bench.ask("\(row).click(); return 'ok';")
            await bench.waitFor(
                "the right pane to return to Activity",
                "return document.querySelector('.v-side-right').dataset.tab === 'activity';"
            )
        }

        // MARK: - Export

        @MainActor
        @Test("Export at 2x PNG returns an image twice the artboard's size")
        func exportAtTwoTimes() async throws {
            let bench = try await Bench("batch.pen")
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01?tab=export"))
            #expect(await bench.ask("return document.querySelector('.v-side-right').dataset.tab;") == "export")

            _ = await bench.ask("""
            window.k92 = {};
            const image = new Image();
            image.onload = () => { window.k92.w = image.naturalWidth; window.k92.h = image.naturalHeight; };
            image.src = document.querySelector('#v-export form').action
              + '?format=png&scale=2';
            return 'ok';
            """)

            await bench.waitFor(
                "the 2x export to decode",
                "return window.k92.w === 800 && window.k92.h === 600;"
            )
        }

        // MARK: - The code tab

        @MainActor
        @Test("Code is the right pane's fourth tab, and the split view is gone")
        func codeIsATabInTheRightPane() async throws {
            let bench = try await Bench("parser-themed-variables.pen")
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/container"))

            // Four pills, no switch, and no seam down the middle of the canvas.
            #expect(await bench.ask(
                "return Array.from(document.querySelectorAll('.v-tabbar .v-tab'))"
                    + ".map((t) => t.dataset.tab).join(',');"
            ) == "activity,details,export,code")
            #expect(await bench.ask("return !!document.querySelector('.v-code-toggle');") == "false")
            #expect(await bench.ask("return !!document.querySelector('.v-grip[data-grip=\"code\"]');") == "false")
            #expect(await bench.ask(
                "return document.getElementById('v-canvas-body').classList.contains('is-split');"
            ) == "false")

            // Like every other panel it is server-rendered on every page, so switching
            // to it is one attribute rather than a round trip.
            #expect(await bench.ask("return !!document.getElementById('v-code');") == "true")
            #expect(await bench.ask(
                "return document.getElementById('v-code').closest('.v-pane').dataset.pane;"
            ) == "code")
            #expect(await bench.ask("return !!document.querySelector('#v-code .v-code-lang');") == "true")
            #expect(await bench.ask("return !!document.querySelector('.v-code-close');") == "false")

            _ = await bench.ask("document.querySelector('.v-tab[data-tab=\"code\"]').click(); return 'ok';")
            await bench.waitFor(
                "the right pane to move to Code",
                "return document.getElementById('v-right').dataset.tab === 'code';"
            )
            await bench.waitFor(
                "the Code pill to be the lit one",
                "return document.querySelector('.v-tab.is-current').dataset.tab === 'code';"
            )
            #expect(await bench.ask("return location.search.includes('tab=code');") == "true")
        }

        @MainActor
        @Test("The code pane's language survives a reload")
        func codeLanguagePersists() async throws {
            let bench = try await Bench("parser-themed-variables.pen")
            defer { Task { await bench.stop() } }

            let page = "/files/\(bench.fileID)/artboards/container?tab=code"
            _ = try await bench.host.boundedLoad(bench.url(page))

            #expect(await bench.ask("return document.querySelector('#v-code').dataset.lang;") == "react")

            _ = await bench.ask("""
            const picker = document.querySelector('.v-code-lang');
            picker.value = 'theme-css';
            picker.dispatchEvent(new Event('change', { bubbles: true }));
            return 'ok';
            """)
            await bench.waitFor(
                "the theme stylesheet to arrive in the pane",
                "return document.querySelector('#v-code').dataset.lang === 'theme-css';"
            )

            // The same URL again: nothing in it names a language, so only the browser's
            // own memory can bring it back.
            _ = try await bench.host.boundedLoad(bench.url(page))
            await bench.waitFor(
                "the reloaded pane to restore the language from localStorage",
                "return document.querySelector('#v-code').dataset.lang === 'theme-css';"
            )
            #expect(await bench.ask(
                "return document.querySelector('#v-code .v-code-body').textContent;"
            ).contains("--bgColor"))
        }

        // MARK: - Resizable panes

        @MainActor
        @Test("Dragging a column handle resizes the pane and the size survives a reload")
        func paneSizePersists() async throws {
            let bench = try await Bench("batch.pen")
            defer { Task { await bench.stop() } }

            let page = "/files/\(bench.fileID)/artboards/Cnv01"
            _ = try await bench.host.boundedLoad(bench.url(page))

            _ = await bench.ask("""
            const grip = document.querySelector('.v-grip[data-grip="left"]');
            const box = grip.getBoundingClientRect();
            const at = (type, x) => grip.dispatchEvent(
              new PointerEvent(type, { bubbles: true, clientX: x, clientY: box.top + 4, pointerId: 1 })
            );
            at('pointerdown', box.left);
            at('pointermove', box.left + 60);
            at('pointerup', box.left + 60);
            return 'ok';
            """)

            await bench.waitFor(
                "the left column to widen",
                "return parseFloat(getComputedStyle(document.querySelector('.v-main'))"
                    + ".getPropertyValue('--v-col-left')) > 380;"
            )

            _ = try await bench.host.boundedLoad(bench.url(page))
            await bench.waitFor(
                "the reloaded page to restore the column width",
                "return parseFloat(getComputedStyle(document.querySelector('.v-main'))"
                    + ".getPropertyValue('--v-col-left')) > 380;"
            )
        }
    }

#endif
