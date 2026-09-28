//
//  HTTPServer.swift
//  WoodcaseViewer
//

import Dispatch
import Foundation
import Network
import Synchronization

/// A minimal HTTP/1.1 server on Network.framework, bound to the loopback interface.
///
/// It listens, accepts, and hands each connection an ``HTTPConnection``. That is all —
/// there is no routing here, no knowledge of what the viewer serves, and no dependency:
/// the whole server is `NWListener` plus a request parser, which is a fair trade against
/// taking on a networking stack to serve a dozen local routes.
///
/// ## Loopback only, on purpose
///
/// `requiredLocalEndpoint` pins the listener to `127.0.0.1`, so `serve` never publishes
/// a designer's work to the network they are sitting on. A viewer for another machine is
/// an SSH tunnel away and is that person's decision to make.
///
/// ## Port 0
///
/// Binding port 0 takes whatever the system offers and reports it through ``port``,
/// which is how the tests run several servers at once without agreeing on numbers.
@available(macOS 15, iOS 18, *)
actor HTTPServer {
    /// Creates a server.
    ///
    /// - Parameters:
    ///   - routes: The table every request is matched against.
    ///   - context: The state handlers work from.
    ///   - startupBudget: How long ``start(port:)`` waits for the listener to report any
    ///     state at all before giving up on it. See ``ResumeOnce/budget``.
    init(
        routes: ViewerRoutes,
        context: ViewerContext,
        startupBudget: Duration = ResumeOnce<Bool>.budget
    ) {
        self.routes = routes
        self.context = context
        self.startupBudget = startupBudget
    }

    private let routes: ViewerRoutes
    private let context: ViewerContext
    private let startupBudget: Duration
    private let queue = DispatchQueue(label: "dev.woodcase.viewer.server")
    private var listener: NWListener?

    /// Every accepted connection that has not yet been cancelled.
    ///
    /// Tracked so ``stop()`` can close them: a listener that stops listening does not
    /// close what it already accepted, and an open event stream would keep the process
    /// alive for as long as its client cared to wait.
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// The port the server is listening on, once it has started.
    private(set) var port: UInt16?

    /// Starts listening.
    ///
    /// - Parameter port: The port to bind, or `0` for whatever the system offers.
    /// - Returns: The bound port.
    /// - Throws: ``StartupError`` if the listener fails, or whatever `NWListener`
    ///   throws for parameters it will not accept.
    func start(port requested: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: requested == 0 ? .any : (NWEndpoint.Port(rawValue: requested) ?? .any)
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [routes, context, queue] connection in
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed:
                    Task { await self.forget(connection) }
                default:
                    break
                }
            }
            let handler = HTTPConnection(
                connection: connection, routes: routes, context: context, queue: queue
            )
            Task {
                await self.remember(connection)
                await handler.start()
            }
        }

        let bind: Result<Void, StartupError> = await ResumeOnce.value(
            within: startupBudget,
            on: queue,
            expiring: {
                listener.cancel()
                return .failure(.unresponsive)
            }
        ) { [queue] box in
            listener.stateUpdateHandler = { state in
                switch Self.outcome(of: state) {
                case .bound: box.resume(with: .success(()))
                case .keepWaiting: break
                case let .failed(error): box.resume(with: .failure(error))
                }
            }
            listener.start(queue: queue)
        }

        do {
            try bind.get()
            guard let bound = listener.port?.rawValue else { throw StartupError.noPort }
            port = bound
            return bound
        } catch {
            // A listener that will not listen must not be left holding a descriptor, and
            // must not be the thing `stop()` later cancels instead of a live one.
            discard(listener)
            throw error
        }
    }

    /// Stops listening and closes every connection still open.
    func stop() {
        if let listener { discard(listener) }
        port = nil

        let open = connections.values
        connections.removeAll()
        for connection in open {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }

    /// Silences a listener and lets it go.
    ///
    /// The handlers are cleared before the cancel so a `.cancelled` state cannot arrive
    /// at a handler whose server has moved on. Nothing is awaiting the listener by the
    /// time this runs — ``start(port:)`` has either been resumed or given up — so no
    /// continuation is stranded by the silence.
    private func discard(_ listener: NWListener) {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        if self.listener === listener { self.listener = nil }
    }

    /// Tracks an accepted connection.
    private func remember(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
    }

    /// Forgets a connection that has closed itself.
    private func forget(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}
