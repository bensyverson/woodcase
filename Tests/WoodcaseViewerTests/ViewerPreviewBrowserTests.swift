//
//  ViewerPreviewBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The preview host's acceptance test: a real browser over a real server, proving
    /// that a state page and a canvas render through the *production* stylesheet.
    ///
    /// One case per colour scheme and nothing more. Everything else about these pages is
    /// markup, and `PreviewRoutesTests` reads markup faster than WebKit can load it; the
    /// one claim only a layout engine can settle is that a state is shown at the
    /// production surface's geometry, so the assertion is a *computed* width. Taking it
    /// in both schemes is what proves the frame rule does not live inside one of them —
    /// and the ground colour is asserted per scheme, or the two cases would be one test
    /// run twice.
    ///
    /// Serialized, one bench per case: a headless WebKit page plus a live server is
    /// heavy, and running several of them beside the rest of the suite is how a run
    /// wedges.
    @Suite(.serialized, .hangGuard)
    struct ViewerPreviewBrowserTests {
        /// A `preview`-shaped server — no files, no log — and a page pointed at it.
        @MainActor
        private struct Bench {
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            init(theme: ColorTheme) async throws {
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [], port: 0, logs: [])
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1440, height: 900),
                    theme: theme,
                    wait: .load,
                    budget: 20
                ))
            }

            /// `localhost` rather than `127.0.0.1`, because App Transport Security
            /// exempts it by name and an ATS failure reads like a dead server.
            func url(_ path: String) -> URL {
                URL(string: "http://localhost:\(port)\(path)")!
            }

            /// Runs a JavaScript body in the page's own world and returns its answer.
            ///
            /// `PageHost.evaluate` transports the value as JSON text, so a string comes
            /// back inside its quotes; decoding here keeps that out of every assertion.
            func ask(_ body: String) async -> String {
                guard let json = try? await host.boundedEvaluate(body, in: .page) else { return "" }
                guard let decoded = try? JSONSerialization.jsonObject(
                    with: Data(json.utf8), options: [.fragmentsAllowed]
                ) as? String else { return json }
                return decoded
            }

            /// The computed width of the outline-column frame on the page as loaded.
            func leftPaneFrameWidth() async -> String {
                await ask("""
                return getComputedStyle(
                    document.querySelector('.v-preview-frame[data-frame="left-pane"]')
                ).width;
                """)
            }

            func stop() async {
                await server.stop()
            }
        }

        /// The first component in the catalog with a state framed as the outline column,
        /// found rather than named so a catalog addition cannot silently retarget this.
        private static var leftPaneState: (component: PreviewComponent, state: PreviewState) {
            for component in PreviewCatalog.all {
                if let state = component.states.first(where: { $0.frame == .leftPane }) {
                    return (component, state)
                }
            }
            fatalError("the catalog declares no leftPane state")
        }

        @MainActor
        @Test(
            "A state page and a canvas render through the real stylesheet, in both colour schemes",
            arguments: [ColorTheme.light, ColorTheme.dark]
        )
        func previewPagesWearTheRealStylesheet(theme: ColorTheme) async throws {
            let bench = try await Bench(theme: theme)
            defer { Task { await bench.stop() } }
            let (component, state) = Self.leftPaneState

            // The state on its own page — the URL a review shot opens.
            _ = try await bench.host.boundedLoad(
                bench.url(ViewerLink.previewState(component: component.slug, state: state.slug))
            )
            #expect(await bench.ask(
                "return getComputedStyle(document.body).backgroundColor;"
            ) == (theme == .dark ? "rgb(22, 22, 21)" : "rgb(246, 245, 241)"))
            #expect(await bench.leftPaneFrameWidth() == "340px")
            #expect(await bench.ask("return document.title;").contains(state.name))

            // …and the same state stacked with its siblings on the canvas.
            _ = try await bench.host.boundedLoad(bench.url(ViewerLink.previewComponent(component.slug)))
            let framed = component.states.count { $0.frame != .page }
            #expect(await bench.ask(
                "return String(document.querySelectorAll('.v-preview-frame').length);"
            ) == String(framed))
            #expect(await bench.leftPaneFrameWidth() == "340px")
            // The anchor a review link pastes actually lands on something.
            #expect(await bench.ask(
                "return document.getElementById('\(state.slug)') ? 'yes' : 'no';"
            ) == "yes")
        }

        @MainActor
        @Test("On a canvas the frame sits on its own line below the permalink")
        func frameSitsBelowThePermalink() async throws {
            let bench = try await Bench(theme: .light)
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(bench.url(ViewerLink.previewComponent("avatar")))
            // A strip frame is an inline box at its natural size, so it is the one that
            // could flow onto the permalink's line — which is what it did until the
            // permalink became a block. Measured, not asserted from the stylesheet:
            // only a layout engine knows where the boxes landed.
            #expect(await bench.ask("""
            const state = document.querySelector('.v-preview-state');
            const link = state.querySelector('.v-preview-permalink').getBoundingClientRect();
            const frame = state.querySelector('.v-preview-frame').getBoundingClientRect();
            return frame.top >= link.bottom ? 'below' : 'beside';
            """) == "below")
        }

        @MainActor
        @Test("The empty page's command block overflows sideways, and says so with a fade")
        func commandBlockScrollsUnderItsFade() async throws {
            let bench = try await Bench(theme: .light)
            defer { Task { await bench.stop() } }

            _ = try await bench.host.boundedLoad(
                bench.url(ViewerLink.previewState(component: "file-empty-page", state: "default"))
            )
            // The block still scrolls rather than wrapping: DESIGN's rule, and the whole
            // reason the fade is there. A measurement, not a style assertion — only a
            // layout engine knows whether the commands ran past the card.
            #expect(await bench.ask("""
            const block = document.querySelector('.v-empty-commands');
            return block.scrollWidth > block.clientWidth ? 'overflows' : 'fits';
            """) == "overflows")
            #expect(await bench.ask("""
            const fade = document.querySelector('.v-empty-block > .v-empty-fade');
            return fade && getComputedStyle(fade).backgroundImage.includes('gradient')
                ? 'faded' : 'bare';
            """) == "faded")
        }
    }

#endif
