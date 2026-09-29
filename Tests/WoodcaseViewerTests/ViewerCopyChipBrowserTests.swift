//
//  ViewerCopyChipBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The two pieces of client behavior ``ViewerScript``'s copy-chip block adds: an id
    /// chip copies without ever selecting or navigating, and the variables panel's
    /// collapse survives a reload.
    ///
    /// A separate suite from ``ViewerBrowserTests``, not a shared one, because a headless
    /// WebKit page plus a live server is heavy enough that two independent benches would
    /// contend if this lived alongside a test another leaf is actively editing.
    @Suite(.serialized, .hangGuard)
    struct ViewerCopyChipBrowserTests {
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

            init() async throws {
                scratch = try ViewerFixtures.scratch()
                file = try ViewerFixtures.copy("batch.pen", into: scratch)
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

            /// Replaces the page's clipboard seam with one the test owns.
            ///
            /// The real seam is the *system* pasteboard, and neither half of it belongs
            /// to this process: `SleepyHollow`'s host is never made key, so
            /// `document.hasFocus()` answers whatever the machine's front window makes it
            /// answer, and WebKit refuses both `navigator.clipboard.writeText` and
            /// `execCommand("copy")` on an unfocused document. A test that clicks and
            /// then asserts "copied" is therefore asserting the state of the desktop; it
            /// passed alone and failed under a loaded suite, which is the classic shape.
            ///
            /// So the page is handed a focused document and a clipboard whose behavior
            /// the test chooses. What is left to assert is exactly what the chip's
            /// handler is responsible for: that it copies the right text, flashes, and
            /// lets no click through to the row.
            ///
            /// - Parameters:
            ///   - writeText: The body of the stubbed `navigator.clipboard.writeText`,
            ///     as JavaScript — it is handed the text as `text`.
            ///   - execCommand: What the stubbed `document.execCommand` returns.
            func stubClipboard(writeText: String, execCommand: Bool = true) async {
                _ = await ask(
                    """
                    window.__copied = null;
                    Object.defineProperty(document, 'hasFocus', {
                      configurable: true, value: () => true
                    });
                    Object.defineProperty(navigator, 'clipboard', {
                      configurable: true,
                      value: { writeText: (text) => { \(writeText) } }
                    });
                    Object.defineProperty(document, 'execCommand', {
                      configurable: true,
                      value: (verb) => {
                        if (verb === 'copy') {
                          window.__copied = document.activeElement.value;
                        }
                        return \(execCommand ? "true" : "false");
                      }
                    });
                    return 'ok';
                    """
                )
            }

            /// Has the page remember the chip's copied flash, rather than polling for it.
            ///
            /// The flash lasts 1.2 s and is then reverted by a `setTimeout`, while one
            /// `evaluate` round trip into a headless page under a loaded suite can take
            /// longer than that. Polling for `is-copied` therefore tests the machine's
            /// spare capacity, not the handler: it passed alone and failed in the full
            /// run. A `MutationObserver` writes the fact down the moment it happens, and
            /// the fact outlives the flash.
            ///
            /// - Parameter chip: A JavaScript expression for the chip to watch.
            func watchForFlash(on chip: String) async {
                _ = await ask(
                    """
                    window.__flashed = null;
                    const chip = \(chip);
                    new MutationObserver(() => {
                      if (chip.classList.contains('is-copied')) {
                        window.__flashed = chip.textContent;
                      }
                    }).observe(chip, {
                      attributes: true, childList: true, subtree: true, characterData: true
                    });
                    return 'ok';
                    """
                )
            }
        }

        @MainActor
        @Test("Clicking an id chip copies it and never selects or navigates the row it sits in")
        func idChipCopiesWithoutSelecting() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            // The artboard page, because the chip under test is a *node* row's — the
            // file's own URL is the map, whose outline lists artboards.
            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(ViewerFile(url: bench.file).id)/artboards/Cnv01")
            )

            await bench.stubClipboard(writeText: "window.__copied = text; return Promise.resolve();")

            let chip = "document.querySelector('.v-outline-row[data-node=\"Ttl01\"] .v-id-chip')"
            let originalText = await bench.ask("return \(chip).textContent;")
            #expect(await bench.ask("return \(chip).querySelector('.v-id-chip-id').textContent;") == "Ttl01")

            await bench.watchForFlash(on: chip)
            _ = await bench.ask("\(chip).click(); return 'ok';")

            await bench.waitFor(
                "the chip to show its copied state",
                "return String(window.__flashed !== null);"
            )
            // The flash is a class: the chip's words are the ones the server wrote, both
            // of them, before, during and after (ymsE0s). The stylesheet picks which shows.
            #expect(await bench.ask("return window.__flashed;") == originalText)
            #expect(await bench.ask("return window.__copied;") == "Ttl01")

            // The click never reached the row: no selection, no navigation.
            #expect(await bench.ask(
                "return document.querySelector('.v-outline-row[data-node=\"Ttl01\"]').classList.contains('is-selected');"
            ) == "false")
            #expect(await bench.ask("return location.search;") == "")
            #expect(await bench.ask("return !!document.querySelector('#v-overlay .v-box.is-selected');") == "false")
        }

        @MainActor
        @Test("A clipboard write that never settles still copies, through the fallback")
        func idChipCopiesWhenTheClipboardPromiseHangs() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url("/files/\(ViewerFile(url: bench.file).id)/artboards/Cnv01")
            )

            // `navigator.clipboard.writeText` does not reject when a page cannot write —
            // it returns a promise that never settles. Awaiting it unguarded swallowed
            // the copy entirely, and the chip never flashed. This is that page.
            await bench.stubClipboard(writeText: "return new Promise(() => {});")

            let chip = "document.querySelector('.v-outline-row[data-node=\"Ttl01\"] .v-id-chip')"
            let originalText = await bench.ask("return \(chip).textContent;")
            await bench.watchForFlash(on: chip)
            _ = await bench.ask("\(chip).click(); return 'ok';")

            await bench.waitFor(
                "the chip to show its copied state despite the hung clipboard promise",
                "return String(window.__flashed !== null);"
            )
            #expect(await bench.ask("return window.__flashed;") == originalText)
            #expect(await bench.ask("return window.__copied;") == "Ttl01")
        }

        @MainActor
        @Test("The variables panel's collapse is remembered across a reload")
        func variablesCollapsePersists() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            #expect(await bench.ask("return document.querySelector('.v-variables').classList.contains('is-collapsed');") == "false")

            _ = await bench.ask("document.querySelector('.v-variables-toggle').click(); return 'ok';")
            #expect(await bench.ask("return document.querySelector('.v-variables').classList.contains('is-collapsed');") == "true")

            _ = try await bench.host.boundedLoad(bench.url("/files/\(ViewerFile(url: bench.file).id)"))
            await bench.waitFor(
                "the reloaded page to restore the collapsed state from localStorage",
                "return document.querySelector('.v-variables').classList.contains('is-collapsed');"
            )
        }
    }

#endif
