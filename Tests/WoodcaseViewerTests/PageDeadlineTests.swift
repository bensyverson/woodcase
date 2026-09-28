//
//  PageDeadlineTests.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing

    /// Proves the browser tests' doors into a page cannot hang, and that every browser
    /// test uses them.
    ///
    /// The suite run wedged at 0 % CPU at least six times (issue `DpQmXu`) with a
    /// headless page and a viewer server alive in the host and no frame of ours but the
    /// server's poll loop: a test suspended on an await that nothing resumed. A page
    /// call was such an await — `callAsyncJavaScript` has no timeout of its own — until
    /// SleepyHollow's `PageHost` gave every call a deadline (leaf `QZ41uc`). The first
    /// case builds a call that never answers and requires the door to name it.
    @Suite("Page deadlines", .hangGuard)
    struct PageDeadlineTests {
        @MainActor
        @Test("An evaluation whose promise never settles fails at its deadline instead of hanging")
        func unsettledEvaluationExpires() async throws {
            let host = PageHost(options: LoadOptions(
                size: ViewportSize(width: 320, height: 240), wait: .load, budget: 20
            ))
            try await host.boundedLoad(#require(URL(string: "about:blank")))

            try await withKnownIssue("the page is built never to answer") {
                // Kept reachable from `window`: WebKit fails a call whose promise has
                // been collected ("Completion handler for function call is no longer
                // reachable"), so only a promise something still holds hangs forever.
                try await host.boundedEvaluate(
                    "await (window.__never = new Promise(() => {})); return 1;", in: .page, within: 2
                )
            } matching: { issue in
                (issue.error as? SleepyError)?.kind == .timeout
            }
            #expect(host.abandonedCall != nil, "a host whose call was abandoned must say so")
        }

        @Test("No browser test calls PageHost's load or evaluate except through a door that names a timeout")
        func everyPageCallIsBounded() throws {
            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            let files: [URL] = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "PageHost+Deadline.swift" }
            let raw = /host\.(load|evaluate)\(/
            var offenders: [String] = []
            for file in files {
                let lines: [Substring] = try String(contentsOf: file, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                for (index, line) in lines.enumerated() where line.contains(raw) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
            #expect(offenders.isEmpty, "use boundedLoad / boundedEvaluate: \(offenders.joined(separator: ", "))")
        }
    }

#endif
