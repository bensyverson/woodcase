//
//  WebViewRenderSlotsTests.swift
//  WoodcaseTests
//

import Testing

/// The gate that bounds how many WebKit renders are in flight at once.
@Suite("WebView render slots")
@MainActor
struct WebViewRenderSlotsTests {
    /// What the tasks in ``boundsConcurrency()`` saw, shared on the main actor.
    @MainActor
    private final class Tally {
        var running = 0
        var peak = 0
        var finished = 0
    }

    @Test("No more than the width run at once, and every waiter gets its turn")
    func boundsConcurrency() async {
        let slots = WebViewRenderSlots(width: 3)
        let tally = Tally()

        let tasks = (0 ..< 10).map { _ in
            Task {
                await slots.acquire()
                tally.running += 1
                tally.peak = max(tally.peak, tally.running)
                try? await Task.sleep(for: .milliseconds(20))
                tally.running -= 1
                tally.finished += 1
                slots.release()
            }
        }
        for task in tasks {
            await task.value
        }

        #expect(tally.peak == 3)
        #expect(tally.finished == 10)
    }

    @Test("A free slot is taken without waiting, and a released one is free again")
    func freeSlotIsImmediate() async {
        let slots = WebViewRenderSlots(width: 1)
        await slots.acquire()
        #expect(slots.available == 0)
        slots.release()
        #expect(slots.available == 1)
    }

    @Test("The width comes from WOODCASE_TEST_WEBVIEW_WIDTH, else the default; nonsense is ignored")
    func widthFromEnvironment() {
        #expect(WebViewRenderSlots.width(from: [:]) == WebViewRenderSlots.defaultWidth)
        #expect(WebViewRenderSlots.width(from: ["WOODCASE_TEST_WEBVIEW_WIDTH": "1"]) == 1)
        #expect(WebViewRenderSlots.width(from: ["WOODCASE_TEST_WEBVIEW_WIDTH": "0"]) == WebViewRenderSlots.defaultWidth)
        #expect(WebViewRenderSlots.width(from: ["WOODCASE_TEST_WEBVIEW_WIDTH": "many"]) == WebViewRenderSlots.defaultWidth)
    }
}
