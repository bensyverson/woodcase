//
//  ViewerSelectionBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// Selecting a node in a real browser: on the render, inside an instance, inside an
    /// instance's instance — and what the right pane's tab bar does about it.
    ///
    /// Its own suite, like ``ViewerRightPaneBrowserTests``: a headless WebKit page plus a
    /// live server is heavy, and one bench per leaf means two of them never contend.
    @Suite(.serialized, .hangGuard)
    struct ViewerSelectionBrowserTests {
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

            /// Clicks one node's box on the render, the way a person does.
            ///
            /// The candidate points are whole *client* pixels, and each is converted back
            /// to layout points before it is accepted, because that is the only version
            /// of the arithmetic the script will ever see: `MouseEvent`'s `clientX` is an
            /// integer, and the stage is drawn at a fraction of life size, so a
            /// fractional coordinate is truncated and then divided by that fraction — an
            /// error the script magnifies into a neighboring box. Aiming in layout
            /// points instead put a click meant for a label two levels up the tree.
            ///
            /// The point is chosen so the *smallest* box containing it is the intended
            /// one, which is the rule the script picks by: a nested child often covers
            /// its parent's middle.
            ///
            /// - Parameter id: The layout node to click.
            /// - Returns: `"ok"` when a point was found and clicked, and the reason
            ///   otherwise, so a test fails on the click rather than on its aftermath.
            @discardableResult
            func clickOnRender(_ id: String) async -> String {
                await ask("""
                const map = JSON.parse(document.getElementById('v-layout').textContent);
                const target = map.nodes.find((n) => n.id === '\(id)');
                if (!target) return 'no box for \(id)';
                const image = document.querySelector('.v-render');
                const box = image.getBoundingClientRect();
                const scale = box.width / map.width;
                const smallest = (x, y) => {
                  let best = null;
                  for (const n of map.nodes) {
                    if (x < n.x || y < n.y || x > n.x + n.width || y > n.y + n.height) continue;
                    if (!best || n.width * n.height < best.width * best.height) best = n;
                  }
                  return best;
                };
                let point = null;
                for (let i = 1; i < 16 && !point; i++) {
                  for (let j = 1; j < 16 && !point; j++) {
                    const clientX = Math.round(box.left + (target.x + (target.width * i) / 16) * scale);
                    const clientY = Math.round(box.top + (target.y + (target.height * j) / 16) * scale);
                    const hit = smallest((clientX - box.left) / scale, (clientY - box.top) / scale);
                    if (hit === target) point = { clientX, clientY };
                  }
                }
                if (!point) return 'no whole pixel of \(id) hit-tests to it';
                image.dispatchEvent(new MouseEvent('click', {
                  bubbles: true,
                  button: 0,
                  clientX: point.clientX,
                  clientY: point.clientY,
                }));
                return 'ok';
                """)
            }

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        // MARK: - Selecting inside an instance

        @MainActor
        @Test("Clicking a node inside a component instance selects its outline row")
        func clickInsideAnInstanceSelectsItsRow() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1"))

            // `Card1` places `CardC`; `Ttl03` is the title inside that instance.
            #expect(await bench.clickOnRender("Card1/Ttl03") == "ok")
            await bench.waitFor(
                "the outline row for the title inside the instance to be selected",
                "return !!document.querySelector("
                    + "'#v-outline .v-outline-row.is-selected[data-node=\"Card1/Ttl03\"]');"
            )
        }

        @MainActor
        @Test("Clicking a node in a nested child component selects its outline row")
        func clickInsideANestedInstanceSelectsItsRow() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1"))

            // `Btn02` is an instance *inside* the component `Card1` places.
            #expect(await bench.clickOnRender("Card1/Btn02/Lbl02") == "ok")
            await bench.waitFor(
                "the outline row for the label inside the nested instance to be selected",
                "return !!document.querySelector("
                    + "'#v-outline .v-outline-row.is-selected[data-node=\"Card1/Btn02/Lbl02\"]');"
            )
        }

        @MainActor
        @Test("Clicking an instance's own frame selects it and Details describes it")
        func clickingAnInstanceFrameShowsItsDetails() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1"))

            // The box expansion roots at `Card1/CardC`, which names no row and which the
            // resolver rejects. The one the render offers has to be the `ref`.
            #expect(await bench.clickOnRender("Card1") == "ok")
            await bench.waitFor(
                "the instance's own outline row to be selected",
                "return !!document.querySelector("
                    + "'#v-outline .v-outline-row.is-selected[data-node=\"Card1\"]');"
            )
            await bench.waitFor(
                "the details of the instance to arrive",
                "return document.querySelector('#v-details .v-detail-name')?.textContent === 'Card';"
            )
            #expect(await bench.ask(
                "return !!document.querySelector('#v-details .v-detail-unresolved');"
            ) == "false")
        }

        // MARK: - The tab bar

        @MainActor
        @Test("Selecting a node moves the highlighted tab, not only the pane")
        func selectionMovesTheHighlight() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1"))

            #expect(await bench.ask(
                "return document.querySelector('.v-tab.is-current').dataset.tab;"
            ) == "activity")

            _ = await bench.ask(
                "document.querySelector('#v-outline .v-outline-row[data-node=\"Card1/Ttl03\"]').click();"
                    + " return 'ok';"
            )
            await bench.waitFor(
                "the pane to move to Details",
                "return document.getElementById('v-right').dataset.tab === 'details';"
            )
            await bench.waitFor(
                "the highlighted tab to follow the pane",
                "return document.querySelector('.v-tab.is-current').dataset.tab === 'details';"
            )
            #expect(await bench.ask(
                "return String(document.querySelectorAll('.v-tab.is-current').length);"
            ) == "1")

            // And back again when the selection is dropped.
            _ = await bench.ask(
                "document.querySelector('#v-outline .v-outline-row[data-node=\"Card1/Ttl03\"]').click();"
                    + " return 'ok';"
            )
            await bench.waitFor(
                "the highlight to return to Activity",
                "return document.querySelector('.v-tab.is-current').dataset.tab === 'activity';"
            )
        }

        @MainActor
        @Test("Selecting from another tab moves both the pane and the pill to Details")
        func selectingFromExportMovesToDetails() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1?tab=export"))
            #expect(await bench.ask(
                "return document.querySelector('.v-tab.is-current').dataset.tab;"
            ) == "export")

            _ = await bench.ask(
                "document.querySelector('#v-outline .v-outline-row[data-node=\"Card1/Ttl03\"]').click();"
                    + " return 'ok';"
            )
            await bench.waitFor(
                "the pill to leave Export for Details",
                "return document.querySelector('.v-tab.is-current').dataset.tab === 'details';"
            )
            #expect(await bench.ask(
                "return document.getElementById('v-right').dataset.tab;"
            ) == "details")
            #expect(await bench.ask(
                "return new URL(location.href).searchParams.get('tab');"
            ) == "details")
        }

        @MainActor
        @Test("Clicking the Details tab with a node selected keeps that node's details")
        func detailsTabKeepsTheSelection() async throws {
            let bench = try await Bench("addressing-nested-instance.pen")
            defer { Task { await bench.stop() } }
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Page1"))

            _ = await bench.ask(
                "document.querySelector('#v-outline .v-outline-row[data-node=\"Card1/Ttl03\"]').click();"
                    + " return 'ok';"
            )
            await bench.waitFor(
                "the details of the selected node to arrive",
                "return document.querySelector('#v-details .v-detail-name')?.textContent === 'Title';"
            )

            // The tab bar was rendered before anything was selected, so its links are the
            // ones that used to drop the selection on the way to their own tab.
            _ = await bench.ask("document.querySelector('.v-tab[data-tab=\"details\"]').click(); return 'ok';")
            await bench.waitFor(
                "the URL to keep the selection",
                "return new URL(location.href).searchParams.get('node') === 'Card1/Ttl03';"
            )
            #expect(await bench.ask(
                "return document.querySelector('#v-details .v-detail-name').textContent;"
            ) == "Title")

            // Away to Activity and back keeps it too.
            _ = await bench.ask("document.querySelector('.v-tab[data-tab=\"activity\"]').click(); return 'ok';")
            await bench.waitFor(
                "Activity to show",
                "return document.getElementById('v-right').dataset.tab === 'activity';"
            )
            _ = await bench.ask("document.querySelector('.v-tab[data-tab=\"details\"]').click(); return 'ok';")
            await bench.waitFor(
                "Details to come back with the same node",
                "return document.querySelector('#v-details .v-detail-name')?.textContent === 'Title';"
            )
            #expect(await bench.ask(
                "return new URL(location.href).searchParams.get('node');"
            ) == "Card1/Ttl03")
        }
    }

#endif
