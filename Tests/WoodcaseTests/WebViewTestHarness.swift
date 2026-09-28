#if os(macOS)

    import CoreGraphics
    import Foundation
    import SleepyHollow

    /// A test utility that renders HTML in a headless WebKit page and captures
    /// a screenshot.
    ///
    /// The WebKit plumbing belongs to SleepyHollow's `PageHost`: it owns the
    /// offscreen web view, the load budget, the settle condition, and the
    /// console capture. This harness only states what the Woodcase tests need —
    /// a viewport, `window.__READY__`, a 2× capture — and translates
    /// SleepyHollow's failures into ``HarnessError``.
    ///
    /// - Important: Must be used on the main actor (WebKit requires the main thread).
    @MainActor
    final class WebViewTestHarness {
        enum HarnessError: Error, CustomStringConvertible {
            case timeout([String])
            case snapshotFailed
            case javaScriptError(String)

            var description: String {
                switch self {
                case let .timeout(errors):
                    if errors.isEmpty {
                        return "WebView timed out waiting for __READY__ signal"
                    }
                    return "WebView timed out. JS errors: \(errors.joined(separator: "; "))"
                case .snapshotFailed:
                    return "The page host returned no capture"
                case let .javaScriptError(msg):
                    return "WebView JS error: \(msg)"
                }
            }
        }

        /// Device pixels per CSS px every capture is taken at.
        ///
        /// Fixed rather than inherited from the machine: the Woodcase side of
        /// every MAE comparison renders at `scale: 2`, and a capture whose
        /// density followed the host's display would silently halve on a
        /// non-Retina Mac.
        private static let captureScale: Int = 2

        /// The script-message name the page posts its ready signal to.
        ///
        /// Fixtures post to it directly as well as setting `window.__READY__`,
        /// so the name is part of the harness's contract with them.
        private static let readyMessageName: String = "ready"

        /// How long a render may take before the harness calls it hung.
        ///
        /// A *not hung* guard, not a measurement, and deliberately far above what a
        /// render costs. The budget bounds the load **and** the ready wait together,
        /// and both run against a machine this suite saturates: at five seconds a
        /// trivial page that threw an error came back as
        /// ``HarnessError/timeout(_:)`` under a loaded soak, naming the budget instead
        /// of the page — the failure that closed leaf `YfptE`. Nothing here asserts on
        /// how long a render took, so the budget's only job is to make a wedged page
        /// fail rather than hang. A test that *wants* a timeout passes its own short
        /// one.
        static let defaultBudget: TimeInterval = 60.0

        /// Renders an HTML file from disk and returns a screenshot as CGImage.
        ///
        /// - Parameters:
        ///   - fileURL: URL of the HTML file to load.
        ///   - viewportSize: The viewport size in points.
        ///   - allowingReadAccessTo: Directory the page is expected to read from.
        ///     Recorded for the caller's intent only: WebKit's own file-URL
        ///     sandbox extension already covers the relative paths these
        ///     fixtures use, and `PageHost` has no read-access root to pass it to.
        ///   - measureContent: When true, after `__READY__` fires, the harness measures
        ///     the `#root` element's `scrollHeight` and resizes the page frame to fit
        ///     before taking the snapshot. Use this for components (not full screens).
        ///   - timeout: Maximum seconds for the load and the wait together. Defaults to
        ///     ``defaultBudget``.
        /// - Returns: A `CGImage` screenshot of the rendered page, at
        ///   ``captureScale`` pixels per point.
        func render(
            fileURL: URL,
            viewportSize: CGSize,
            allowingReadAccessTo _: URL,
            measureContent: Bool = false,
            timeout: TimeInterval = defaultBudget
        ) async throws -> CGImage {
            var watch = PhaseStopwatch("render:\(fileURL.deletingPathExtension().lastPathComponent)")
            let started = Date()
            let host: PageHost = Self.checkOutHost(budget: timeout, viewportSize: viewportSize)
            defer { Self.checkIn(host, budget: timeout) }
            watch.lap("host")

            // Subscribe before the load, so a page that is ready before its
            // load event has its signal buffered rather than missed.
            let readySignals: AsyncStream<String> = host.messages(named: Self.readyMessageName, in: .page)

            let errors = StreamedConsoleErrors()
            let consoleMessages: AsyncStream<String> = host.messages(
                named: PageHost.consoleMessageName,
                in: .page
            )
            let pump = Task {
                for await text in consoleMessages {
                    errors.record(text)
                }
            }
            defer { pump.cancel() }

            // `ViewportSize` is whole points; the exact (possibly fractional)
            // size the caller asked for is what the layout must see.
            host.webView.frame = CGRect(origin: .zero, size: viewportSize)
            // Transparent backdrop, so a component that does not paint its own
            // background compares against the Woodcase render's transparency
            // rather than against white.
            host.webView.setValue(false, forKey: "drawsBackground")

            do {
                _ = try await host.load(fileURL)
            } catch let error as SleepyError where error.kind == .timeout {
                throw HarnessError.timeout(errors.messages)
            }
            watch.lap("load")

            let remaining: TimeInterval = max(0.1, timeout + started.timeIntervalSinceNow)
            guard await Self.waitForSignal(on: readySignals, within: remaining) else {
                throw HarnessError.timeout(errors.messages)
            }
            watch.lap("ready")

            let raised: [String] = try await Self.pageErrors(on: host)
            if !raised.isEmpty {
                throw HarnessError.javaScriptError(raised.joined(separator: "; "))
            }
            watch.lap("errors")

            if measureContent {
                let text: String = try await host.evaluate(
                    "return document.getElementById('root').scrollHeight;", in: .page
                )
                if let measuredHeight = Double(text), measuredHeight > 0 {
                    host.webView.frame = CGRect(
                        origin: .zero,
                        size: CGSize(width: viewportSize.width, height: measuredHeight)
                    )
                }
            }
            watch.lap("measure")

            // Wait for fonts to finish loading, then allow a final paint.
            _ = try await host.evaluate("await document.fonts.ready; return true;", in: .page)
            try await Task.sleep(for: .milliseconds(150))
            watch.lap("fonts")

            let shot = try ShotOperation(region: .viewport, scale: ShotScale(factor: Self.captureScale))
            let shotOutput: ShotOperation.Output = try await shot.execute(on: host)
            guard let captured: ShotImage = shotOutput.images.first else {
                throw HarnessError.snapshotFailed
            }
            let image: CGImage = try ShotCapture(decoding: captured).image
            watch.lap("snapshot")
            watch.total()
            return image
        }

        /// Signals readiness on an uncaught error, so a page that breaks fails
        /// as ``HarnessError/javaScriptError(_:)`` rather than sitting out its
        /// budget and reporting a timeout it did not earn.
        ///
        /// Page world and document start: the flag it sets is the page's own,
        /// and the errors it must see are the page's own.
        static let readyOnErrorScript = InjectedScript(
            source: """
            window.addEventListener('error', function () { window.__READY__ = true; });
            window.addEventListener('unhandledrejection', function () { window.__READY__ = true; });
            """,
            injectAt: .documentStart,
            world: .page
        )

        /// Posts the ready signal as soon as `window.__READY__` is set.
        ///
        /// The wait is deliberately *pushed* by the page rather than pulled by
        /// ``WaitCondition/predicate(_:)``: the host's predicate loop re-checks
        /// from the main actor, and Woodcase's suite saturates the main actor
        /// with parallel renderer work, which starves the poll into a timeout
        /// the page did not earn. A page-side `setTimeout` runs on WebKit's own
        /// clock and costs one main-actor hop, when it fires.
        ///
        /// Document end, page world: it reads the page's own global, and it
        /// must not start before the document's own scripts have.
        static let readySignalScript = InjectedScript(
            source: """
            (function () {
                function check() {
                    if (window.__READY__) {
                        window.webkit.messageHandlers.\(readyMessageName).postMessage("ready");
                    } else {
                        setTimeout(check, 16);
                    }
                }
                check();
            })();
            """,
            injectAt: .documentEnd,
            world: .page
        )

        /// Whether the page signalled within `seconds`.
        private static func waitForSignal(on signals: AsyncStream<String>, within seconds: TimeInterval) async -> Bool {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await _ in signals {
                        return true
                    }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(seconds))
                    return false
                }
                let signalled: Bool = await group.next() ?? false
                group.cancelAll()
                return signalled
            }
        }

        /// Everything the page raised that was not an explicit `console` call:
        /// uncaught exceptions and unhandled rejections.
        ///
        /// Read from SleepyHollow's page-side buffer rather than from the
        /// message stream, so nothing depends on script-message delivery racing
        /// the settle.
        private static func pageErrors(on host: PageHost) async throws -> [String] {
            let log: ConsoleLog = try await ConsoleOperation().execute(on: host)
            return log.messages
                .filter { $0.origin != .console }
                .map { "\($0.label): \($0.text)" }
        }
    }

    // MARK: - StreamedConsoleErrors

    /// The console messages that arrived while a load was in flight.
    ///
    /// A timed-out page may not answer another round trip, so the timeout path
    /// reports what the page already pushed instead of asking it again.
    @MainActor
    private final class StreamedConsoleErrors {
        private(set) var messages: [String] = []

        /// Records one JSON entry from `PageHost.consoleMessageName`.
        func record(_ text: String) {
            guard let message = try? JSONDecoder().decode(ConsoleMessage.self, from: Data(text.utf8)) else {
                return
            }
            guard message.level == .error else { return }
            messages.append("\(message.label): \(message.text)")
        }
    }

#endif
