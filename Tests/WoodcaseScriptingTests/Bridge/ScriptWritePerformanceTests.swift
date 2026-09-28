//
//  ScriptWritePerformanceTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// What a script that alternates writes and reads costs.
///
/// A read after a write must see settled layout, so every write drops the settled tree and
/// the next read pays for a whole pipeline again. That makes write-then-read the one shape
/// of script the host can be slow at, and this is the measurement of it. Three shapes are
/// timed rather than one, because the interesting number is the difference between them:
/// writes alone, reads alone behind the cache, and the two alternating. The figures and the
/// command that reproduces them are recorded in <doc:WoodcasePerformance>.
///
/// **The document is not in the repository.** The measurement is stated for a large
/// hand-authored design system that lives outside version control, so the test is skipped
/// unless `$WOODCASE_SCRIPT_PERF` names a `.pen` file:
///
/// ```sh
/// WOODCASE_SCRIPT_PERF=local/<document>.pen \
///   swift test --filter ScriptWritePerformanceTests 2>&1 | grep WRITE-READ
/// ```
///
/// It asserts nothing about the clock. A timing measured while other builds run is not a
/// timing (`project/gotchas.md`), and a budget nobody can reproduce from a checkout has no
/// business failing a suite; the lines it prints are the whole of its answer.
@Suite("the write-then-read cost")
struct ScriptWritePerformanceTests {
    /// The document to measure, from the environment.
    private static var document: URL? {
        guard let path = ProcessInfo.processInfo.environment["WOODCASE_SCRIPT_PERF"],
              !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// How many operations one repetition runs.
    private static let count = 100

    /// How many repetitions the reported minimum is taken over.
    private static let repetitions = 3

    /// One shape of script, and the script it runs.
    private enum Shape: String, CaseIterable {
        /// `count` writes, no reads: what the writes themselves cost.
        case writes

        /// `count` reads, no writes: what the settled-tree cache is worth, since only
        /// the first of them settles.
        case reads

        /// `count` write-and-read pairs: one settle per read, which is the shape being
        /// budgeted.
        case pairs

        /// The JavaScript, ending in a number so the run has an answer to check.
        ///
        /// - Parameters:
        ///   - root: The node to rename, which is the cheapest edit that still changes
        ///     the document — the question is what the *read* after it costs.
        ///   - count: How many operations to run.
        /// - Returns: The script.
        func script(root: String, count: Int) -> String {
            let write = "doc.set('#\(root)', { 'common.name': 'measured ' + i });"
            let read = "rows = doc.tree().length;"
            let body = switch self {
            case .writes: write + " rows = 1;"
            case .reads: read
            case .pairs: write + " " + read
            }
            return """
            let rows = 0;
            for (let i = 0; i < \(count); i++) { \(body) }
            rows;
            """
        }
    }

    @Test("writes, reads, and the two alternating", .enabled(if: ScriptWritePerformanceTests.document != nil))
    func writeThenRead() throws {
        let url = try #require(Self.document)
        let parsed = try PenParser.parse(contentsOf: url)
        // Read once up front so every line below names the document's size, including
        // the shape that never reads.
        let sized = ScriptHost.run(
            [.text("doc.tree().length", name: "<perf>")], over: EditableDocument(from: parsed)
        )
        guard case let .int(rows) = sized.result else {
            Issue.record("the document's row count could not be read")
            return
        }

        for shape in Shape.allCases {
            var samples: [Duration] = []
            for _ in 0 ..< Self.repetitions {
                let document = EditableDocument(from: parsed)
                let root = try #require(document.rootOrder.first, "the document has no roots")
                let start = ContinuousClock.now
                let run = ScriptHost.run(
                    [.text(shape.script(root: root, count: Self.count), name: "<perf>")],
                    over: document
                )
                samples.append(ContinuousClock.now - start)
                #expect(run.error == nil, "\(run.error?.message ?? "")")
            }
            let minimum = try #require(samples.min())
            print("""
            WRITE-READ \(url.lastPathComponent) \(rows) rows \
            \(shape.rawValue) ×\(Self.count) \
            min \(Self.milliseconds(minimum)) ms over \(Self.repetitions) runs \
            (\(Self.milliseconds(minimum / Self.count)) ms each) \
            samples \(samples.map { "\(Self.milliseconds($0))" }.joined(separator: ", "))
            """)
        }
    }

    /// A duration in milliseconds, to one decimal place.
    ///
    /// - Parameter duration: The measured time.
    /// - Returns: The milliseconds.
    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let raw = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return (raw * 10).rounded() / 10
    }
}
