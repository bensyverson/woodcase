//
//  ViewerHosting.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Synchronization
import Woodcase
import WoodcaseViewer

/// What the two viewer verbs share: finding a port, opening a browser, and waiting to
/// be interrupted.
///
/// `serve` and `preview` are the same process in two shapes — one over the files a
/// project has been editing, one over the preview catalog and nothing else — so the
/// parts that are neither's decision live here rather than in whichever verb was
/// written first. Each verb keeps what is genuinely its own: what to serve, what to
/// print, and which URL to open.
enum ViewerHosting {
    /// Where the automatic port search starts, and the address a bookmark expects.
    ///
    /// A person who runs the viewer twice in a week usually finds it at this same
    /// address — nothing else is competing for it — but the port is not fixed: a
    /// second server already running bumps to 7334 rather than refusing outright, the
    /// way `job serve` behaves.
    static let defaultPort: UInt16 = 7333

    /// How many ports past ``defaultPort`` (or `--port-base`) the automatic search
    /// tries before giving up.
    ///
    /// 100 is generous enough for "a person forgot to stop yesterday's server a dozen
    /// times over" without searching forever once the whole range is genuinely
    /// unavailable — a sandbox denial in particular stops the search on the first try
    /// regardless, since no later port would fare any better.
    static let autoIncrementSpan: UInt16 = 100

    /// The loopback address a bound port is reached at.
    ///
    /// - Parameters:
    ///   - port: The bound port.
    ///   - path: The path to land on. `/` is the dashboard; `preview` lands on the
    ///     catalog instead.
    /// - Returns: The URL as text.
    static func address(port: UInt16, path: String = "/") -> String {
        "http://127.0.0.1:\(port)\(path)"
    }

    /// Binds the viewer's listener: exactly `pinned` when one was named, otherwise a
    /// search from `searchBase` upward across ``autoIncrementSpan`` candidates.
    ///
    /// A sandbox denial ends the search immediately, pinned or not — retrying a
    /// different port number never helps when the environment forbids listening on
    /// any of them — while an ordinary bind failure (the port is simply taken) only
    /// ends a pinned attempt; during a search it just tries the next candidate.
    ///
    /// - Parameters:
    ///   - server: The server to start.
    ///   - files: The `.pen` files to serve. Empty for `preview`, which serves none.
    ///   - logs: The activity logs to read. Empty for `preview`, which reads none.
    ///   - pinned: The `--port` value, or `nil` to search.
    ///   - searchBase: Where the search starts when `pinned` is `nil`.
    /// - Returns: The port that was bound.
    /// - Throws: ``CommandFailure`` — a sandbox denial or an exhausted search end the
    ///   process at exit 5, a busy pinned port at exit 3.
    static func bind(
        _ server: ViewerServer,
        files: [URL],
        logs: [ActivityLog],
        pinned: UInt16?,
        searchBase: UInt16
    ) async throws -> UInt16 {
        if let pinned {
            do {
                return try await server.start(files: files, port: pinned, logs: logs)
            } catch {
                throw failure(for: error, port: pinned)
            }
        }

        var lastError: (any Error)?
        var highestTried = searchBase
        for offset in 0 ... Int(autoIncrementSpan) {
            let candidateValue = Int(searchBase) + offset
            // A search base near UInt16.max (a test picking an OS-assigned ephemeral
            // port) must stop rather than overflow; the real 7333 base never gets
            // close.
            guard candidateValue <= Int(UInt16.max) else { break }
            let candidate = UInt16(candidateValue)
            highestTried = candidate
            do {
                return try await server.start(files: files, port: candidate, logs: logs)
            } catch {
                if SandboxDenial.matches(error) {
                    throw failure(for: error, port: candidate)
                }
                lastError = error
            }
        }
        throw CommandFailure(
            message: "No port between \(searchBase) and \(highestTried) is free"
                + (lastError.map { ": \($0)" } ?? "")
                + ". Free one, or pass --port to pin a specific one.",
            exitCode: .environment
        )
    }

    /// Renders one bind failure as the message and exit code the caller sees.
    ///
    /// - Parameters:
    ///   - error: What the listener threw.
    ///   - port: The port that failed to bind.
    /// - Returns: The failure to throw.
    private static func failure(for error: any Error, port: UInt16) -> CommandFailure {
        guard SandboxDenial.matches(error) else {
            return CommandFailure(
                message: "Port \(port) is in use. Free it, or run without --port "
                    + "to let woodcase try the next one.",
                exitCode: .conflict
            )
        }
        return CommandFailure(
            message: "Cannot bind port \(port). \(SandboxDenial.sentence(forbidding: "listening on a port"))",
            exitCode: .environment
        )
    }

    /// Opens the URL in the default browser.
    ///
    /// A failure here is not the command's failure: the server is up and the URL is on
    /// stdout, so the worst case is that the person clicks it themselves.
    ///
    /// - Parameter address: The URL to open.
    static func openInBrowser(_ address: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [address]
        do {
            try process.run()
        } catch {
            StandardError.write("Could not open a browser: \(error). Open \(address) yourself.")
        }
    }

    /// Interruptions, as a sequence with one element per signal.
    ///
    /// `SIGINT` and `SIGTERM` are ignored at the C level first, which is what stops the
    /// default handler killing the process before the dispatch source ever runs — and
    /// killing it is exactly what would leave open sockets and half-written state
    /// behind. A verb waits for the first element and then stops the server properly.
    ///
    /// - Returns: The stream. Cancelling it cancels the underlying sources.
    static func interruptions() -> AsyncStream<Int32> {
        AsyncStream { continuation in
            let sources = Sources()
            for number in [SIGINT, SIGTERM] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(
                    signal: number, queue: DispatchQueue.global()
                )
                source.setEventHandler { continuation.yield(number) }
                source.resume()
                sources.keep(source)
            }
            continuation.onTermination = { _ in sources.cancel() }
        }
    }

    /// Holds the signal sources alive for as long as the stream is.
    ///
    /// A `DispatchSourceSignal` stops delivering the moment it is released, so the
    /// sources cannot be locals of ``interruptions()``.
    private final class Sources: Sendable {
        /// The sources being kept.
        private let sources = Mutex<[any DispatchSourceSignal]>([])

        /// Keeps one alive.
        ///
        /// - Parameter source: The source to hold.
        func keep(_ source: any DispatchSourceSignal) {
            sources.withLock { $0.append(source) }
        }

        /// Cancels every source held.
        func cancel() {
            let held = sources.withLock { held in
                defer { held.removeAll() }
                return held
            }
            held.forEach { $0.cancel() }
        }
    }
}
