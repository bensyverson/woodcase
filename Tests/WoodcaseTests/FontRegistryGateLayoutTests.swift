//
//  FontRegistryGateLayoutTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Laying text out goes through ``FontRegistryGate`` too, not only resolving its font.
///
/// Core Text's typesetter reaches `fontd` by itself — a font's script flags the first time
/// it shapes with it, a fallback face for a character the font lacks — so a layout running
/// beside a gated resolution put a second request in flight. That is how
/// `ChangedArtboardsTests.expandedCopiesCount` hung for 75 minutes (issue 6StvbE): one
/// thread inside the gate and one typesetting outside it, each in a synchronous XPC wait
/// `fontd` never answered, and six more queued on the gate.
///
/// Each test holds the gate on another thread and lays out text whose font is already
/// resolved, so only the typesetting could need the gate. Every wait is bounded: a layout
/// that ignored the gate finishes while it is held and fails the first expectation, and
/// one that waited forever would fail the second rather than hang the run.
struct FontRegistryGateLayoutTests {
    /// How long a layout gets to finish while the gate is held: far longer than one takes.
    private static let whileHeld: TimeInterval = 1

    /// How long a layout gets once the gate is released: anything past this is a hang.
    private static let afterRelease: TimeInterval = 60

    /// Whether `layout` finished while another thread held the gate, and whether it finished
    /// once that thread let go.
    private static func run(_ layout: @escaping @Sendable () -> Void) -> (whileHeld: Bool, afterRelease: Bool) {
        let holding = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            FontRegistryGate.withAccess {
                holding.signal()
                release.wait()
            }
        }
        holding.wait()
        Thread.detachNewThread {
            layout()
            finished.signal()
        }
        let whileHeld = finished.wait(timeout: .now() + whileHeld) == .success
        release.signal()
        let afterRelease = whileHeld || finished.wait(timeout: .now() + afterRelease) == .success
        return (whileHeld, afterRelease)
    }

    /// A text no earlier layout set, so no cache answers for it.
    private static func freshText() -> String {
        "Typeset \(UUID().uuidString) afresh"
    }

    @Test("Measuring text waits for the gate: the layout engine's typesetting reaches fontd")
    func measuringTakesTheGate() {
        // Resolve the font first, so the measurement below needs the gate only to typeset.
        _ = PenTextMeasurer.measure("Warm", fontFamily: "Helvetica", fontSize: 13)

        let outcome = Self.run {
            _ = PenTextMeasurer.measure(Self.freshText(), fontFamily: "Helvetica", fontSize: 13, maxWidth: 120)
        }

        #expect(!outcome.whileHeld, "measured while another thread held the font registry")
        #expect(outcome.afterRelease)
    }

    @Test("Setting a text for drawing waits for the gate: the renderer's framesetter reaches fontd")
    func drawingLayoutTakesTheGate() throws {
        let style = try #require(PenTextLayoutSample.multiLine.first).style
        _ = PenTextLayout(text: "Warm", style: style, box: CGSize(width: 200, height: 100))

        let outcome = Self.run {
            _ = PenTextLayout(text: Self.freshText(), style: style, box: CGSize(width: 200, height: 100))
        }

        #expect(!outcome.whileHeld, "laid out while another thread held the font registry")
        #expect(outcome.afterRelease)
    }
}
