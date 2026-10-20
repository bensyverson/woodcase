//
//  TextInkCacheGateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``TextInkCache``'s lock is never held around a measurement, so it never nests with
/// ``FontRegistryGate``.
///
/// A text's ink is measured by a Core Text layout, which waits for the gate
/// (`project/2026-10-20-fontd-wedge-and-the-layout-gate.md`). Were the cache's lock held
/// across it, every other thread's lookup — a hit included — would queue behind a layout
/// that is itself queued behind the gate, and a lookup made from inside the gate would
/// order the two locks both ways. Each wait here is bounded, so a regression fails rather
/// than hangs the run.
struct TextInkCacheGateTests {
    /// How long a lookup gets while another thread measures under the held gate: far
    /// longer than a dictionary read takes.
    private static let whileHeld: TimeInterval = 1

    /// How long the measurement gets once the gate is released: anything past this is a hang.
    private static let afterRelease: TimeInterval = 60

    @Test("while one text is measured behind the held gate, another thread's lookup is answered")
    func theLockIsFreeDuringAGatedMeasurement() {
        let cache = TextInkCache(fontGeneration: { 0 })
        var style = PenTextStyle()
        style.fontSize = 14
        let kept = TextInkCache.Key(text: "Kept", style: style, runs: [], width: 100, height: 20)
        let measuring = TextInkCache.Key(text: "Measuring", style: style, runs: [], width: 100, height: 20)
        let keptInk = PenRect(x: 0, y: 2, width: 30, height: 14)
        _ = cache.inkBounds(of: kept, measure: { _ in keptInk })

        let holding = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let inMeasurement = DispatchSemaphore(value: 0)
        let measured = DispatchSemaphore(value: 0)
        let answered = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            FontRegistryGate.withAccess {
                holding.signal()
                release.wait()
            }
        }
        holding.wait()
        Thread.detachNewThread {
            _ = cache.inkBounds(of: measuring, measure: { _ in
                inMeasurement.signal()
                return FontRegistryGate.withAccess { PenRect(x: 0, y: 0, width: 1, height: 1) }
            })
            measured.signal()
        }
        inMeasurement.wait()
        Thread.detachNewThread {
            let hit = cache.inkBounds(of: kept, measure: { _ in nil })
            if hit == keptInk { answered.signal() }
        }

        let answeredWhileHeld = answered.wait(timeout: .now() + Self.whileHeld) == .success
        release.signal()
        let finished = measured.wait(timeout: .now() + Self.afterRelease) == .success

        #expect(answeredWhileHeld, "a lookup waited on a measurement queued behind the font registry gate")
        #expect(finished)
        #expect(cache.measuredCount == 2)
    }
}
