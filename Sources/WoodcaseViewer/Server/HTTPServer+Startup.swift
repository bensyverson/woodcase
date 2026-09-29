//
//  HTTPServer+Startup.swift
//  WoodcaseViewer
//

import Foundation
import Network

@available(macOS 15, iOS 18, *)
extension HTTPServer {
    /// Why a server could not start.
    enum StartupError: Error, CustomStringConvertible {
        /// The listener reported a failure instead of becoming ready.
        case listenerFailed(String)
        /// The listener is retrying a bind it will not win, and would retry forever.
        case listenerWaiting(String)
        /// The listener reported no state at all inside the startup budget.
        case unresponsive
        /// The listener became ready without reporting a port, which should not happen.
        case noPort

        var description: String {
            switch self {
            case let .listenerFailed(reason):
                "The viewer's listener could not start: \(reason)"
            case let .listenerWaiting(reason):
                """
                The viewer's listener is waiting for a port it cannot have: \(reason). \
                Free the port, or serve on another one with `woodcase serve --port <n>`.
                """
            case .unresponsive:
                """
                The viewer's listener did not answer at all — no state, ready or failed, \
                inside \(ResumeOnce<Bool>.budget). Retry `woodcase serve`; if it keeps \
                happening the system's networking stack is not answering.
                """
            case .noPort:
                "The viewer's listener started without binding a port."
            }
        }
    }

    /// What one listener state means to a server still waiting to bind.
    enum StartupOutcome {
        /// The listener is listening; read its port.
        case bound
        /// The state precedes an answer, so wait for the next one.
        case keepWaiting
        /// The listener will not be listening; report this instead of waiting.
        case failed(StartupError)
    }

    /// Classifies a listener state, so that no reachable state resumes nothing.
    ///
    /// Every case is named on purpose. A state the handler silently ignores is a
    /// continuation nobody resumes, which is a whole test run stopped with no frame of
    /// ours in the sample to explain it — the failure this classification exists to make
    /// impossible. Only `.setup` genuinely precedes an answer.
    ///
    /// `.waiting` is the interesting one. `NWListener` reports it for a port it cannot
    /// have *yet* and then retries on its own schedule, indefinitely. That is the right
    /// behavior for a listener on a real interface waiting for a network path; it is the
    /// wrong one here, because the viewer binds loopback, where there is no path to wait
    /// for and a port that is taken now will be taken in an hour. So waiting is reported.
    ///
    /// - Parameter state: The state the listener just reported.
    /// - Returns: What the start should do about it.
    static func outcome(of state: NWListener.State) -> StartupOutcome {
        switch state {
        case .ready:
            .bound
        case .setup:
            .keepWaiting
        case let .waiting(error):
            .failed(.listenerWaiting(String(describing: error)))
        case let .failed(error):
            .failed(.listenerFailed(String(describing: error)))
        case .cancelled:
            .failed(.listenerFailed("canceled before it was ready"))
        @unknown default:
            .failed(.listenerFailed("an unrecognized listener state: \(state)"))
        }
    }
}
