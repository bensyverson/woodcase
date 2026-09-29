#if os(macOS)

    import CoreGraphics
    import Foundation
    import SleepyHollow

    /// The page hosts renders borrow instead of building their own.
    ///
    /// A `PageHost` is a `WKWebView` with its own **non-persistent** data
    /// store, which means a fresh web content process and an empty resource
    /// cache. Building one per render made every fixture page re-read and
    /// re-compile the 3 MB `babel.min.js` and the 400 KB Tailwind build from
    /// cold; reused, WebKit keeps them, and a page load fell from 255 ms to
    /// 113 ms (see `project/2026-08-29-test-suite-speed.md`).
    ///
    /// Reuse is safe because repeated `load(_:)` is what `PageHost` is built
    /// for: each navigation resets the page's facts, its globals and the
    /// console capture's page-side buffer, which is every piece of per-load
    /// state this harness reads. The injected scripts are WebKit *user*
    /// scripts installed once at `init`, so they re-run on every document.
    ///
    /// Reuse is *not* safe for a host that gave up on a call: WebKit cannot take a
    /// call back, so the page may still be running it or holding the content process
    /// the next render needs. ``checkIn(_:budget:)`` discards such a host.
    extension WebViewTestHarness {
        /// Page hosts no render is currently using, keyed by load budget.
        ///
        /// A pool rather than one host per budget because `PageHost` refuses a
        /// *concurrent* load on one host, and `WebViewTestHarnessTests` is not
        /// serialized. A checked-out host is simply absent from the pool, so
        /// overlapping renders get hosts of their own and hand them back.
        ///
        /// Keyed by budget because the budget is fixed at `PageHost.init` and
        /// is what bounds a load: a host built for
        /// ``WebViewTestHarness/defaultBudget`` cannot honor a caller asking to
        /// fail after 2. There are two keys in practice — every render that
        /// expects a page to work takes the default, and the one test that
        /// expects a timeout asks for a short budget of its own.
        static var idleHosts: [TimeInterval: [PageHost]] = [:]

        /// Whether `WOODCASE_TEST_NO_HOST_POOL` has switched reuse off, so
        /// every render builds its own host as this harness used to.
        ///
        /// It exists so the value of reuse stays measurable: together with
        /// `WOODCASE_TEST_PROFILE` it is the A/B behind the load figures in
        /// `project/2026-08-29-test-suite-speed.md`, holding everything else
        /// constant. Nothing but a measurement should set it.
        static let isPoolingDisabled: Bool = ProcessInfo.processInfo
            .environment["WOODCASE_TEST_NO_HOST_POOL"] != nil

        /// Takes a host for `budget` out of the pool, building one if none is
        /// idle.
        ///
        /// - Parameters:
        ///   - budget: the load budget the host must have been built for.
        ///   - viewportSize: the initial frame for a host that has to be built.
        ///     Every render overwrites `webView.frame` anyway, because
        ///     `ViewportSize` is whole points and the layout must see the
        ///     exact, possibly fractional, size asked for.
        /// A host is built with a call budget of ``callAllowance`` past `budget`, so each
        /// call into the page — an evaluation, the snapshot — has a deadline far past
        /// anything a healthy render needs.
        ///
        /// - Returns: a host with no load in flight.
        static func checkOutHost(budget: TimeInterval, viewportSize: CGSize) -> PageHost {
            if !isPoolingDisabled, let reused = idleHosts[budget]?.popLast() { return reused }
            let options = LoadOptions(
                size: ViewportSize(width: Int(viewportSize.width), height: Int(viewportSize.height)),
                scripts: [readyOnErrorScript, readySignalScript],
                budget: budget,
                callBudget: budget + callAllowance
            )
            return PageHost(options: options)
        }

        /// How much longer than the load budget one call into the page may take.
        ///
        /// A *not hung* guard sized from observation: at load ~240 snapshots took over
        /// two minutes to answer at all (`project/2026-09-26-the-page-that-never-answers.md`),
        /// and a call that times out fails its render where a slow one would have passed.
        static let callAllowance: TimeInterval = 240

        /// Returns `host` to the pool for the next render — unless it gave up on a
        /// call, in which case it is dropped and the next render builds its own.
        ///
        /// The page it last showed is left alone: the next `load` replaces the
        /// document, and a page kept alive is one whose failure a debugger can
        /// still inspect.
        ///
        /// - Parameters:
        ///   - host: the host to hand back.
        ///   - budget: the budget it was built for, and its key.
        static func checkIn(_ host: PageHost, budget: TimeInterval) {
            guard host.abandonedCall == nil else { return }
            idleHosts[budget, default: []].append(host)
        }
    }

#endif
