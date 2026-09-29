//
//  HTTPServerStartupTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Network
import Testing
@testable import WoodcaseViewer

/// What each `NWListener` state means to a server that is still waiting to bind.
///
/// The audit these tests encode: a state the handler does nothing with is a continuation
/// nobody resumes, and the whole test run then stops with no frame of ours to explain it.
/// So every state a listener can report is named here, and only the one that genuinely
/// precedes an answer is allowed to keep waiting.
@Suite("HTTPServer startup", .hangGuard)
struct HTTPServerStartupTests {
    @Test("a ready listener is bound")
    func readyBinds() {
        guard case .bound = HTTPServer.outcome(of: .ready) else {
            Issue.record("a ready listener must bind")
            return
        }
    }

    @Test("setup is the only state that resumes nothing")
    func setupKeepsWaiting() {
        guard case .keepWaiting = HTTPServer.outcome(of: .setup) else {
            Issue.record("setup precedes an answer and must keep waiting")
            return
        }
    }

    /// `.waiting` was the hole. `NWListener` reports it for a port it cannot have yet and
    /// then retries on its own schedule, indefinitely; the handler ignored it, so a
    /// listener that never got its port left `start` suspended for the life of the
    /// process. The viewer binds loopback, where there is no network path to wait for, so
    /// waiting is a failure to report rather than a state to sit in.
    @Test("waiting is reported as a failure, not sat in")
    func waitingFails() {
        let reported = NWError.posix(.EADDRINUSE)
        guard case let .failed(error) = HTTPServer.outcome(of: .waiting(reported)) else {
            Issue.record("a waiting listener must resolve the start")
            return
        }
        #expect("\(error)".contains(String(describing: reported)))
        #expect("\(error)".contains("--port"))
    }

    @Test("a failed listener reports its reason")
    func failedReportsReason() {
        let reported = NWError.posix(.EINVAL)
        guard case let .failed(error) = HTTPServer.outcome(of: .failed(reported)) else {
            Issue.record("a failed listener must resolve the start")
            return
        }
        #expect("\(error)".contains(String(describing: reported)))
    }

    @Test("a listener canceled before it is ready fails rather than hangs")
    func canceledFails() {
        guard case .failed = HTTPServer.outcome(of: .cancelled) else {
            Issue.record("a canceled listener must resolve the start")
            return
        }
    }

    @Test("the unresponsive error names the seam and what to do about it")
    func unresponsiveErrorTeaches() {
        let description = String(describing: HTTPServer.StartupError.unresponsive)
        #expect(description.contains("did not answer"))
        #expect(description.lowercased().contains("retry"))
    }

    /// The whole point, end to end: a start whose state handler never fires throws
    /// instead of wedging the run. A budget of zero is what a dead handler looks like
    /// from the outside, and the assertion is that the call *returns* at all.
    @Test("a start that never hears from its listener throws")
    func startGivesUp() async throws {
        let home = try ViewerFixtures.scratch()
        let server = HTTPServer(
            routes: ViewerRoutes(),
            context: ViewerFixtures.context(files: [], home: home),
            startupBudget: .zero
        )
        await #expect(throws: HTTPServer.StartupError.self) {
            _ = try await server.start(port: 0)
        }
        await server.stop()
    }
}
