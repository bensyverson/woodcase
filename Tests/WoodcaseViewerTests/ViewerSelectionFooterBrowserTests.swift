//
//  ViewerSelectionFooterBrowserTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing
    import Woodcase
    @testable import WoodcaseViewer

    /// The selection footer's overflow ladder, measured where a review shot sees it.
    ///
    /// The footer is a row of fixed facts around one shrinking path, so it only stays
    /// whole if it sheds the least essential facts *before* the fixed ones outgrow the
    /// row. Markup cannot see whether that happens; only a laid-out rect can. The bench is
    /// `woodcase preview`'s shape at the review loop's own 1280×800 window, because the
    /// frames — and the page preview's canvas column — are measured against that window.
    ///
    /// Serialized, one bench per case, for the reason ``ViewerPreviewBrowserTests`` gives.
    @Suite(.serialized, .hangGuard)
    struct ViewerSelectionFooterBrowserTests {
        @MainActor
        private struct Bench {
            let server: ViewerServer
            let host: PageHost
            let port: UInt16

            init() async throws {
                server = ViewerServer(pages: { _ in ViewerPages.routes() })
                port = try await server.start(files: [], port: 0, logs: [])
                host = PageHost(options: LoadOptions(
                    size: ViewportSize(width: 1280, height: 800),
                    theme: .light,
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

            func stop() async {
                await server.stop()
            }
        }

        /// Everything wrong with the footer's layout, in one sentence, or `whole`.
        ///
        /// Reported together so a failure names which fact broke: every item still inside
        /// the row's padding box, the path still drawing *something*, and every fixed fact
        /// that is shown drawn at its full width rather than squeezed.
        private static let footerReport = """
        const footer = document.querySelector('.v-selection');
        const row = footer.getBoundingClientRect();
        const pad = parseFloat(getComputedStyle(footer).paddingRight);
        const problems = [];
        for (const item of footer.children) {
          if (getComputedStyle(item).display === 'none') continue;
          const box = item.getBoundingClientRect();
          if (box.right > row.right - pad + 0.5) {
            problems.push(`${item.className} ends at ${Math.round(box.right)} past ${Math.round(row.right - pad)}`);
          }
          if (item.scrollWidth > item.clientWidth + 1 && !item.classList.contains('v-selection-path')) {
            problems.push(`${item.className} is squeezed`);
          }
        }
        const path = footer.querySelector('.v-selection-path');
        if (path && path.getBoundingClientRect().width < 40) {
          problems.push(`the path is ${Math.round(path.getBoundingClientRect().width)}px wide`);
        }
        return problems.length ? `${problems.join('; ')} (row ${Math.round(row.width)}px)` : 'whole';
        """

        @MainActor
        @Test("The artboard page's footer stays whole when the clip warning shows (sGWNUd)")
        func clippedFooterStaysWholeOnThePage() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("artboard-page", "default")
            // The fixture selects the node hanging off its parent, so the sentence is there.
            #expect(await bench.ask("return String(!!document.querySelector('.v-selection .v-clip'));") == "true")
            #expect(await bench.ask(Self.footerReport) == "whole")
        }

        @MainActor
        @Test(
            "Every selection-bar state keeps its footer whole in its frame (sGWNUd)",
            arguments: ["default", "nothing-selected", "clipped", "long-path", "narrow-pane"]
        )
        func everyStateStaysWhole(state: String) async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("selection-bar", state)
            #expect(await bench.ask(Self.footerReport) == "whole")
        }

        @MainActor
        @Test("The narrow-pane state is pinned below 560 px, sheds the rect and revision, and front-truncates (4GVELx)")
        func narrowPaneShedsAndTruncates() async throws {
            let bench = try await Bench()
            defer { Task { await bench.stop() } }
            try await bench.open("selection-bar", "narrow-pane")
            let width = await Double(bench.ask(
                "return String(document.querySelector('.v-selection').getBoundingClientRect().width);"
            )) ?? 0
            #expect(width > 480 && width < 560, "the footer is \(width)px wide")
            #expect(await bench.ask("""
            return ['.v-selection-rect', '.v-selection-rev']
              .map((s) => getComputedStyle(document.querySelector(s)).display).join(',');
            """) == "none,none")
            // A character the ellipsis ate reports a zero-width rect (gotchas.md).
            #expect(await bench.ask("""
            const path = document.querySelector('.v-selection-path');
            const text = path.querySelector('bdi').firstChild;
            const width = (at) => {
              const range = document.createRange();
              range.setStart(text, at); range.setEnd(text, at + 1);
              return range.getBoundingClientRect().width;
            };
            return String(path.scrollWidth > path.clientWidth
              && width(text.length - 1) > 0 && width(0) === 0);
            """) == "true")
        }
    }

#endif
