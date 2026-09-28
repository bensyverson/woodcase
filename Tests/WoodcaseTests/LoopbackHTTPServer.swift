//
//  LoopbackHTTPServer.swift
//  WoodcaseTests
//

#if os(macOS)
    import Foundation
    import Network

    /// A one-trick HTTP server on 127.0.0.1 that answers every connection with the same
    /// canned bytes — or with nothing at all — so a client's handling of a status line,
    /// a proxy challenge or a stalled peer can be tested without the network.
    ///
    /// It parses nothing: whatever the client sends, the reply is the same. Good enough to
    /// stand in for an origin server (`GET`) or a proxy (`CONNECT`).
    final class LoopbackHTTPServer: @unchecked Sendable {
        /// What the server does with a connection.
        enum Reply {
            /// Writes these bytes once the client has spoken, then closes.
            case respond(String)
            /// Reads the request and never answers, holding the connection open.
            case silence
        }

        /// The port the listener was given.
        let port: UInt16

        private let listener: NWListener
        private let connections: HeldConnections

        private init(listener: NWListener, connections: HeldConnections, port: UInt16) {
            self.listener = listener
            self.connections = connections
            self.port = port
        }

        /// A status line, headers for an empty-or-short body, and the body.
        static func response(status: Int, reason: String, body: String = "", headers: [String] = []) -> Reply {
            let lines = ["HTTP/1.1 \(status) \(reason)", "Content-Length: \(body.utf8.count)", "Connection: close"]
                + headers
            return .respond(lines.joined(separator: "\r\n") + "\r\n\r\n" + body)
        }

        /// Starts a server on an ephemeral loopback port and waits until it listens.
        static func start(reply: Reply) async throws -> LoopbackHTTPServer {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            let queue = DispatchQueue(label: "LoopbackHTTPServer")
            let box = HeldConnections()
            // The handler must be set before `start`, or the listener fails with EINVAL
            // (project/gotchas.md, 2026-08-30).
            listener.newConnectionHandler = { connection in
                box.add(connection)
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                    guard case let .respond(text) = reply else { return }
                    connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
                let once = Once()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                    case let .failed(error):
                        once.run { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
            return LoopbackHTTPServer(listener: listener, connections: box, port: port)
        }

        /// Stops listening and drops every connection.
        func stop() {
            listener.cancel()
            connections.cancelAll()
        }

        /// The connections a server has accepted, kept alive so a silent server holds them.
        private final class HeldConnections: @unchecked Sendable {
            private let lock = NSLock()
            private var connections: [NWConnection] = []

            func add(_ connection: NWConnection) {
                lock.withLock { connections.append(connection) }
            }

            func cancelAll() {
                lock.withLock { connections }.forEach { $0.cancel() }
            }
        }

        /// Runs a block at most once, so a continuation is never resumed twice.
        private final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false

            func run(_ body: () -> Void) {
                let first = lock.withLock {
                    defer { done = true }
                    return !done
                }
                if first { body() }
            }
        }
    }
#endif
