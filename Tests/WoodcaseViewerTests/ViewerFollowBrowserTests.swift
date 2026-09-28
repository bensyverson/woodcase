//
//  ViewerFollowBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// Following an identity, and the unread dots — the two pieces of the viewer that
    /// only exist once a real write reaches a real page.
    ///
    /// A suite of its own, like ``ViewerCopyChipBrowserTests``: a headless WebKit page
    /// plus a live server plus a render is heavy, and each bench takes a fresh port —
    /// which is also what keeps the unread marks in `localStorage` from leaking between
    /// tests, since a port is an origin.
    @Suite(.serialized, .hangGuard)
    struct ViewerFollowBrowserTests {
        /// A server, a page pointed at it, and a fixture with a theme axis to pin.
        @MainActor
        private struct Bench {
            let scratch: URL
            let file: URL
            let log: ActivityLog
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            init() async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy("batch.pen", into: scratch)
                try Bench.declareThemeAxis(in: file)
                log = ActivityLog(home: scratch)
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [file], port: 0, log: log)
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1440, height: 900),
                    wait: .load,
                    budget: 20
                ))
            }

            /// Gives the copied fixture a real theme axis, so "a theme pin survives"
            /// is asserted against an axis the document actually declares rather than
            /// against a parameter nothing reads.
            static func declareThemeAxis(in url: URL) throws {
                let data = try Data(contentsOf: url)
                guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ViewerError.renderFailed(artboard: "", file: url.path)
                }
                json["themes"] = ["Mode": ["Light", "Dark"]]
                try JSONSerialization
                    .data(withJSONObject: json, options: [.sortedKeys])
                    .write(to: url, options: .atomic)
            }

            /// The file's id, as every URL spells it.
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

            /// Waits for the event stream to say it is connected, which is the point
            /// after which a write is guaranteed to reach the page.
            func waitForLive() async {
                await waitFor(
                    "the event stream to connect",
                    "return document.getElementById('v-live').dataset.state === 'live';"
                )
            }

            /// Renames a node as an identity, which is one logged write.
            func write(_ node: String, to name: String, as identity: String) async throws {
                try await PenFileTransaction.run(
                    at: file, identity: identity, log: log, timeout: ViewerFixtures.lockBudget
                ) { _, recorder in
                    try recorder.apply(.updateCommon(EditOperation.UpdateCommon(
                        nodeID: node, common: PenNodeCommon(name: name)
                    )))
                }
            }

            func stop() async {
                await server.stop()
                try? FileManager.default.removeItem(at: scratch)
            }
        }

        @MainActor
        @Test("Following ana moves the page on her write and stays put on bob's")
        func followsOneIdentity() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Brd01?theme=Mode%3ADark&follow=ana")
            )
            await bench.waitForLive()
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Brd01")

            // bob writes into a different artboard. Follow is on ana, so the page must
            // stay exactly where it is — the change still lands, which is what makes
            // "did not navigate" an assertion rather than a race.
            try await bench.write("Ttl01", to: "Bob's title", as: "bob")
            await bench.waitFor(
                "bob's write to reach the page",
                "return document.getElementById('v-activity').textContent.includes('bob');"
            )
            #expect(await bench.ask("return location.pathname;").hasSuffix("/artboards/Brd01"))
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Brd01")

            // ana writes into that same artboard, and the page follows her to it.
            try await bench.write("Cd201", to: "Ana's card", as: "ana")
            await bench.waitFor(
                "the page to follow ana to the artboard she wrote",
                "return document.getElementById('v-stage').dataset.artboard === 'Cnv01';"
            )
            #expect(await bench.ask("return location.pathname;").hasSuffix("/artboards/Cnv01"))
            #expect(await bench.ask(
                "return document.getElementById('v-outline').textContent.includes(\"Ana's card\");"
            ) == "true")
        }

        @MainActor
        @Test("A theme pin survives a followed write")
        func themePinSurvivesAFollowedWrite() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(bench.fileID)/artboards/Brd01?theme=Mode%3ADark&follow=anyone")
            )
            await bench.waitForLive()
            #expect(await bench.ask("return location.search;").contains("theme=Mode%3ADark"))

            try await bench.write("Cd201", to: "Moved", as: "ana")
            await bench.waitFor(
                "the page to follow the write to Cnv01",
                "return document.getElementById('v-stage').dataset.artboard === 'Cnv01';"
            )

            // The pin is still in the URL, still on the control, and still on the image.
            #expect(await bench.ask("return location.search;").contains("theme=Mode%3ADark"))
            #expect(await bench.ask("return location.search;").contains("follow=anyone"))
            #expect(await bench.ask(
                "return document.querySelector('.v-theme-select').selectedOptions[0].textContent;"
            ) == "Dark")
            #expect(await bench.ask("return document.querySelector('.v-render').src;")
                .contains("theme=Mode%3ADark"))
        }

        @MainActor
        @Test("An artboard a change touched shows a dot until it is viewed")
        func unreadDotUntilViewed() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Brd01"))
            await bench.waitForLive()

            // A fresh browser has no history to draw dots from: unread starts now.
            #expect(await bench.ask(
                "return String(document.querySelectorAll('[data-artboard][data-unread]').length);"
            ) == "0")

            try await bench.write("Ttl01", to: "Touched", as: "bob")
            // `Cnv01` is the artboard before this one, so the footer's own step link is a
            // view of it and carries the dot.
            await bench.waitFor(
                "a dot on the artboard the write touched",
                "return document.querySelector('[data-artboard=\"Cnv01\"]').dataset.unread === '1';"
            )
            // And the way up says the news is somewhere else in the file.
            #expect(await bench.ask(
                "return document.querySelector('.v-crumb-map').dataset.unread;"
            ) == "1")

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01"))
            // The next write's mark is recorded by *this* page, off the event stream, so
            // the stream has to be connected before it is made. Without this the write
            // can land while the reload is still connecting, the mark is never taken,
            // and the map below waits out its whole bound for a dot nobody wrote.
            await bench.waitForLive()
            await bench.waitFor(
                "the dot to clear once that artboard is viewed",
                "return !document.querySelector('.v-crumb-map').dataset.unread;"
            )
            // The artboard on screen is being viewed, so no view of it carries one.
            #expect(await bench.ask(
                "return String([...document.querySelectorAll('[data-artboard=\"Cnv01\"]')]"
                    + ".every((element) => !element.dataset.unread));"
            ) == "true")

            // And the map shows the same marks on its boxes. `Lbl01` lives in `Cmp01`,
            // which is neither the artboard on screen nor the one just viewed.
            try await bench.write("Lbl01", to: "Elsewhere", as: "bob")
            // Wait for the mark *before* navigating. A dot lives in this browser's
            // `localStorage`, written by the `change` handler when the event arrives over
            // the stream; a page that navigates away first never runs that handler, and
            // the mark is then lost for good — so the wait on the map afterwards can
            // never rescue it, however long it is. This is the one step in the test that
            // assumed the write would be delivered faster than a page load, and under a
            // loaded suite it is not: it failed two of five runs of
            // `scripts/soak-tests 5 <log> --load 2` before this wait was added.
            await bench.waitFor(
                "the write to be marked unread before the page navigates away",
                "return localStorage.getItem('woodcase.unread:\(bench.fileID):Cmp01') === '1';"
            )
            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)"))
            await bench.waitFor(
                "the map to dot the artboard that changed",
                "return document.querySelector('#v-map .v-map-board[data-artboard=\"Cmp01\"]').dataset.unread === '1';"
            )
        }

        @MainActor
        @Test("Manual navigation drops follow to nobody and offers to resume")
        func manualNavigationDropsFollow() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(bench.fileID)/artboards/Cnv01?follow=ana"))
            await bench.waitForLive()
            #expect(await bench.ask(
                "return document.querySelector('.v-follow-select').selectedOptions[0].value;"
            ) == "ana")

            _ = await bench.ask("document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').click(); return 'ok';")

            await bench.waitFor(
                "follow to drop to nobody, remembering who it was",
                "return location.search.includes('follow=paused%3Aana');"
            )
            await bench.waitFor(
                "the control to offer a one-click resume",
                "return document.getElementById('v-follow').textContent.includes('resume following ana');"
            )
            #expect(await bench.ask(
                "return document.querySelector('.v-follow-select').selectedOptions[0].value;"
            ) == "nobody")
            // The selection the click asked for still happened.
            #expect(await bench.ask("return location.search.includes('node=Ttl01');") == "true")

            // And a write by ana no longer moves the page.
            try await bench.write("Cmp01", to: "Elsewhere", as: "ana")
            await bench.waitFor(
                "ana's write to reach the page",
                "return document.getElementById('v-activity').textContent.includes('Elsewhere') || document.getElementById('v-outline').textContent.includes('Elsewhere');"
            )
            #expect(await bench.ask("return document.getElementById('v-stage').dataset.artboard;") == "Cnv01")
        }
    }

#endif
