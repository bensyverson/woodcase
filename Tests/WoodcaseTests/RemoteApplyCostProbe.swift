//
//  RemoteApplyCostProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a collaborator's one-property change costs a session to apply, early and late in
/// a long burst, on Penumbra's 2,464-node perf board — printed as `PROBE` lines.
///
/// Two sessions edit one board, as a window and its collaborator do: the window nudges a
/// card on each step, as a drag does, and the collaborator recolors one of four cards,
/// as Penumbra's `edit-burst` probe does. Each side applies the other's change as a
/// remote one, and each remote apply is timed.
///
/// A measurement, not a check: it runs only when given the board (write it with
/// Penumbra's `scripts/perf-board <dir>`), in a release build, and its figures mean
/// something only beside `uptime`:
///
/// ```sh
/// WOODCASE_REMOTE_COST_BOARD=<dir>/perf-large.pen swift test -c release -Xswiftc -enable-testing --filter RemoteApplyCostProbe
/// ```
@MainActor
struct RemoteApplyCostProbe {
    /// The cards the collaborator recolors, as Penumbra's burst does.
    static let recolored = ["card-00015", "card-00045", "card-00060", "card-00323"]

    /// Milliseconds in a duration.
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
    }

    /// The median and p90 of a window of samples, formatted.
    static func summary(_ samples: ArraySlice<Duration>) -> String {
        let sorted = samples.sorted()
        return String(format: "median %.3f ms p90 %.3f ms", ms(sorted[sorted.count / 2]), ms(sorted[sorted.count * 9 / 10]))
    }

    @Test("Remote apply cost on the 2,464-node perf board", .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_REMOTE_COST_BOARD"] != nil))
    func probe() throws {
        let board = try PenParser.parse(contentsOf: URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["WOODCASE_REMOTE_COST_BOARD"])))
        let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
        let window = DocumentSession(document: board, author: ana, collaborative: true)
        let collaborator = DocumentSession(document: board, author: claude, collaborative: true)
        print("PROBE nodes \(window.document.nodes.count)")
        let clock = ContinuousClock()
        let cold = clock.measure { _ = window.document.documentRevision }
        let warm = clock.measure { _ = window.document.documentRevision }
        print(String(format: "PROBE document revision cold %.3f ms warm %.3f ms", Self.ms(cold), Self.ms(warm)))

        var windowSide: [Duration] = []
        var collaboratorSide: [Duration] = []
        let steps = 500
        for step in 0 ..< steps {
            let nudge = try window.submit(.local(LocalEdit(operations: [.setProperties(EditOperation.SetProperties(
                nodeID: "card-00030", properties: ["common.x": .int(40 + step % 50)]
            ))])))
            try collaboratorSide.append(clock.measure {
                _ = try collaborator.submit(.remote(nudge.broadcast, from: ana))
            })

            let card = Self.recolored[step % Self.recolored.count]
            let fill = step % 8 < 4 ? "#FDE68A" : "#FFFFFF"
            let recolor = try collaborator.submit(.local(LocalEdit(operations: [.setProperties(EditOperation.SetProperties(
                nodeID: card, properties: ["kind.fills": .string(fill)]
            ))])))
            try windowSide.append(clock.measure {
                _ = try window.submit(.remote(recolor.broadcast, from: claude))
            })
        }
        for (label, samples) in [("window applies a recolor", windowSide), ("collaborator applies a nudge", collaboratorSide)] {
            print("PROBE \(label) first 50: \(Self.summary(samples[0 ..< 50]))")
            print("PROBE \(label) 225-275: \(Self.summary(samples[225 ..< 275]))")
            print("PROBE \(label) last 50: \(Self.summary(samples[(steps - 50) ..< steps]))")
        }
    }
}
