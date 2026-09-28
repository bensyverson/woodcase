// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links
// AppKit and the Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import SleepyHollow
    import Testing

    /// The harness's host pool hands a render a host that is free — never one still
    /// busy with a call the page did not answer.
    ///
    /// SleepyHollow gives up on a call past its deadline, but WebKit cannot take the
    /// call back: the page may still be running it, or holding the content process the
    /// next call needs. A pooled host with an abandoned call would carry that stall into
    /// the next render, so the pool discards it.
    @Suite("WebViewTestHarness host pool", .hangGuard)
    @MainActor
    struct WebViewTestHarnessHostPoolTests {
        /// A pool key no other test uses, so the hosts this test checks in and out are
        /// its own.
        private static let budget: TimeInterval = 7.5

        private static let viewport = CGSize(width: 64, height: 64)

        @Test("A host whose call was abandoned is discarded rather than reused")
        func abandonedHostIsDiscarded() async throws {
            try #require(!WebViewTestHarness.isPoolingDisabled, "the pool is switched off in this run")
            let host = WebViewTestHarness.checkOutHost(budget: Self.budget, viewportSize: Self.viewport)
            _ = try await host.load(#require(URL(string: "about:blank")))

            // A healthy host goes back into the pool and comes out again.
            WebViewTestHarness.checkIn(host, budget: Self.budget)
            let reused = WebViewTestHarness.checkOutHost(budget: Self.budget, viewportSize: Self.viewport)
            #expect(reused === host)

            // Held from `window`: WebKit fails a call whose promise has been collected,
            // so only a held promise never answers.
            await #expect(throws: SleepyError.self) {
                try await host.evaluate(
                    "await (window.__never = new Promise(() => {})); return 1;", in: .page, budget: 1
                )
            }
            #expect(host.abandonedCall != nil)

            WebViewTestHarness.checkIn(host, budget: Self.budget)
            let next = WebViewTestHarness.checkOutHost(budget: Self.budget, viewportSize: Self.viewport)
            #expect(next !== host, "a host with an abandoned call went back into the pool")
            WebViewTestHarness.checkIn(next, budget: Self.budget)
        }
    }

#endif
