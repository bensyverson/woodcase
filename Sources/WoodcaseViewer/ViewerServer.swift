//
//  ViewerServer.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The viewer, whole: an HTTP/SSE server on the loopback interface, a watcher over the
/// files it serves, a warm render cache, and the coordinator that turns a write on disk
/// into an event on the page.
///
/// ```swift
/// let server = ViewerServer()
/// let port = try await server.start(files: [url], port: 0, logs: ActivityLogLocation.logs(for: [url]))
/// // … http://127.0.0.1:\(port)/ …
/// await server.stop()
/// ```
///
/// `woodcase serve` is a five-line consumer of this: parse the flags, start, print the
/// URL, wait for the process to be interrupted, stop.
///
/// ## Everything stops
///
/// ``stop()`` closes the open event streams, ends the watcher's stream, cancels the
/// coordinator's tasks and cancels the listener. Nothing is left holding the process
/// open, which is what lets a test start a dozen servers in one run.
@available(macOS 15, iOS 18, *)
public actor ViewerServer {
    /// Creates a server.
    ///
    /// - Parameter pages: Builds the page routes to register *before* the data
    ///   endpoints — the seam the viewer page plugs into. The default registers none,
    ///   which leaves the placeholder pages in place.
    public init(pages: @escaping @Sendable (ViewerContext) -> ViewerRoutes = { _ in ViewerRoutes() }) {
        self.pages = pages
    }

    /// Builds the page routes registered ahead of the data endpoints.
    private let pages: @Sendable (ViewerContext) -> ViewerRoutes

    /// The running server's state, or `nil` before ``start(files:port:logs:)``.
    private var running: Running?

    /// What a started server holds.
    private struct Running {
        let context: ViewerContext
        let http: HTTPServer
        let watcher: FileWatcher
        let coordinator: ChangeCoordinator
        let port: UInt16
    }

    /// The port the server is listening on, or `nil` if it is not running.
    public var port: UInt16? {
        running?.port
    }

    /// The context handlers work from, or `nil` if the server is not running.
    ///
    /// Exposed so a caller — a test, or `serve` printing a summary — can ask what is
    /// being served without going through HTTP.
    public var context: ViewerContext? {
        running?.context
    }

    /// The address to open, or `nil` if the server is not running.
    public var address: URL? {
        running.map { URL(string: "http://127.0.0.1:\($0.port)/")! }
    }

    /// Starts serving.
    ///
    /// - Parameters:
    ///   - files: The .pen files to serve. Empty adopts every file the activity logs
    ///     have seen, which is the cross-file dashboard.
    ///   - port: The port to bind, or `0` for whatever the system offers.
    ///   - logs: The activity logs to read identity, history and presence from — one per
    ///     project the served files belong to. ``Woodcase/ActivityLogLocation/logs(for:workingDirectory:environment:)``
    ///     is what resolves them; the server is handed the answer.
    /// - Returns: The bound port.
    /// - Throws: Whatever the listener throws. A server already running is stopped first,
    ///   so starting twice is not a way to leak a listener.
    @discardableResult
    public func start(
        files: [URL],
        port: UInt16 = 0,
        logs: [ActivityLog]
    ) async throws -> UInt16 {
        await stop()

        let index = ViewerFileIndex(files: files)
        await index.adoptFilesFromLogs(logs)
        let context = ViewerContext(
            files: index, renders: RenderCache(), logs: logs, events: SSEHub()
        )

        var routes = pages(context)
        routes.add(contentsOf: ViewerEndpoints.routes())

        let watcher = FileWatcher()
        let coordinator = ChangeCoordinator(context: context)
        await coordinator.start(watcher: watcher)
        await watcher.watch(index.files.map(\.url))

        // A page that connects between two edits must still know who is around.
        await context.events.setGreeting {
            let presence = await coordinator.currentPresence
            return [(try? SSEEvent(id: 0, name: .presence, payload: presence))].compactMap(\.self)
        }

        let http = HTTPServer(routes: routes, context: context)
        let bound = try await http.start(port: port)
        running = Running(
            context: context, http: http, watcher: watcher,
            coordinator: coordinator, port: bound
        )

        // Warming is worth doing and not worth waiting for: the first request should
        // not block on rendering every artboard of every file. The map's small variants
        // follow the full-size renders rather than interleaving with them — the artboard
        // somebody opens first is what they are actually waiting for — so a map opened
        // later is a wall of thumbnails instead of a wall of empty boxes.
        Task { [index, renders = context.renders] in
            for file in await index.files {
                await renders.warm(file)
            }
            for file in await index.files {
                await renders.warmThumbnails(file)
            }
        }
        return bound
    }

    /// Starts serving, reading one activity log.
    ///
    /// - Parameters:
    ///   - files: The .pen files to serve.
    ///   - port: The port to bind, or `0` for whatever the system offers.
    ///   - log: The one activity log to read.
    /// - Returns: The bound port.
    /// - Throws: Whatever ``start(files:port:logs:)`` throws.
    @discardableResult
    public func start(files: [URL], port: UInt16 = 0, log: ActivityLog) async throws -> UInt16 {
        try await start(files: files, port: port, logs: [log])
    }

    /// Stops serving and releases everything.
    public func stop() async {
        guard let running else { return }
        self.running = nil
        await running.coordinator.stop()
        await running.watcher.stop()
        await running.context.events.closeAll()
        await running.http.stop()
    }
}
