//
//  WebViewRenderSlots.swift
//  WoodcaseTests
//

/// A gate on how many WebKit renders are in flight at once, across every WebView suite.
///
/// A render spends most of its time waiting on WebKit's content process — the page load
/// and its fonts were 57 % of a React board in 2026-09-28's profile — while the main
/// actor sits idle, so overlapping a few renders keeps that wait off the suite's critical
/// path. The bound is what keeps it safe: unbounded, every board of a parameterized suite
/// would load at once and starve the page-pushed ready signal the way the old poll was
/// starved (`project/2026-08-29-test-suite-speed.md`, section 4). The time a render waits
/// here is not charged to its load budget, which starts once it has a host.
///
/// Waiters are served in arrival order. Cancellation is not honoured: a test that stops
/// waiting still takes its slot and releases it.
@MainActor
final class WebViewRenderSlots {
    /// How many renders may be in flight when `WOODCASE_TEST_WEBVIEW_WIDTH` does not say.
    nonisolated static let defaultWidth = 4

    /// Slots free right now.
    private(set) var available: Int

    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// A gate with `width` slots.
    ///
    /// - Parameter width: How many holders may be in at once.
    init(width: Int) {
        available = width
    }

    /// The width a run asked for: `WOODCASE_TEST_WEBVIEW_WIDTH` when it is a positive
    /// whole number, else ``defaultWidth``. `1` serializes every render, as the suites
    /// did before the gate.
    ///
    /// - Parameter environment: The process environment.
    /// - Returns: The width.
    nonisolated static func width(from environment: [String: String]) -> Int {
        guard let text = environment["WOODCASE_TEST_WEBVIEW_WIDTH"], let width = Int(text), width > 0 else {
            return defaultWidth
        }
        return width
    }

    /// Waits for a free slot and takes it.
    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Gives a slot back, to the longest waiter if there is one.
    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
