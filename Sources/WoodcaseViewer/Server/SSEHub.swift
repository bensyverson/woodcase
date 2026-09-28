//
//  SSEHub.swift
//  WoodcaseViewer
//

import Foundation

/// Somewhere an event stream's bytes can be written.
///
/// The hub talks to this rather than to `NWConnection`, so the fan-out — many clients,
/// heartbeats, close-on-stop — is testable without a socket, and the one implementation
/// that does own a socket has nothing in it but `send`.
public protocol SSEWriter: Sendable {
    /// Writes text to the stream.
    ///
    /// - Parameter text: The bytes to send, already in the SSE wire format.
    /// - Returns: `false` if the stream is gone, so the hub can drop the client.
    @discardableResult
    func write(_ text: String) async -> Bool

    /// Closes the stream.
    func close() async
}

/// Every open `/events` stream, and the fan-out to them.
///
/// Clients come and go while the server runs, so the hub owns the list, hands out the
/// monotonic event ids, and drops a client the moment a write fails — a browser tab
/// closing must not leave a stream to write into forever.
///
/// A heartbeat comment goes to every client every ``heartbeat`` while any are connected.
/// It exists so an idle stream is not mistaken for a dead one by the browser, and so a
/// disappeared client is noticed even when nothing has changed.
public actor SSEHub {
    /// Creates a hub.
    ///
    /// - Parameter heartbeat: How often to send the keep-alive comment.
    public init(heartbeat: Duration = .seconds(15)) {
        self.heartbeat = heartbeat
    }

    /// How often the keep-alive comment goes out.
    public let heartbeat: Duration

    /// The connected clients, by the id the hub gave them.
    private var clients: [Int: any SSEWriter] = [:]

    /// The next client id.
    private var nextClientID = 1

    /// The id of the last event sent, which is also the `id:` line's value.
    private var lastEventID = 0

    /// The task sending heartbeats while clients are connected.
    private var heartbeatTask: Task<Void, Never>?

    /// How many streams are open.
    public var clientCount: Int {
        clients.count
    }

    /// The id of the last event broadcast.
    public var lastEvent: Int {
        lastEventID
    }

    /// What a client is sent the moment it connects.
    ///
    /// A stream that says nothing until something changes leaves a page with no state
    /// at all — no presence, nothing. The server sets this to the current presence
    /// snapshot, and the hub writes it to each new client before any live event.
    private var greeting: (@Sendable () async -> [SSEEvent])?

    /// Sets what each new client is greeted with.
    ///
    /// - Parameter greeting: Produces the events to send to a client on connection.
    public func setGreeting(_ greeting: @escaping @Sendable () async -> [SSEEvent]) {
        self.greeting = greeting
    }

    /// Adds a client, greets it, and starts the heartbeat if it is the first.
    ///
    /// - Parameter writer: Where to write this client's events.
    /// - Returns: The client's id, for ``remove(_:)``.
    @discardableResult
    public func add(_ writer: any SSEWriter) async -> Int {
        let id = nextClientID
        nextClientID += 1
        clients[id] = writer
        startHeartbeat()

        if let greeting {
            for event in await greeting() where clients[id] != nil {
                if await writer.write(event.wireFormat) == false {
                    clients.removeValue(forKey: id)
                }
            }
        }
        return id
    }

    /// Drops a client without closing it — for a stream that has already gone away.
    ///
    /// - Parameter id: The client's id.
    public func remove(_ id: Int) {
        clients.removeValue(forKey: id)
        if clients.isEmpty { stopHeartbeat() }
    }

    /// Sends an event to every client, dropping any whose write fails.
    ///
    /// - Parameters:
    ///   - name: Which stream the event belongs to.
    ///   - payload: The value to encode as the event's `data`.
    /// - Throws: Whatever `JSONEncoder` throws for a payload it cannot encode. Nothing
    ///   is sent in that case: a client must never receive half an event.
    public func broadcast(_ name: SSEEvent.Name, payload: some Encodable) async throws {
        lastEventID += 1
        let event = try SSEEvent(id: lastEventID, name: name, payload: payload)
        await send(event.wireFormat)
    }

    /// Sends an already-built event to every client.
    ///
    /// - Parameter event: The event to send. Its `id` is used as given.
    public func broadcast(_ event: SSEEvent) async {
        lastEventID = max(lastEventID, event.id)
        await send(event.wireFormat)
    }

    /// Closes every open stream and stops the heartbeat.
    ///
    /// This is what makes `stop()` terminate: a stream nobody closes keeps its
    /// connection — and the process — alive indefinitely.
    public func closeAll() async {
        stopHeartbeat()
        let open = clients.values
        clients.removeAll()
        for writer in open {
            await writer.close()
        }
    }

    // MARK: - Private

    /// Writes text to every client, dropping the ones that refuse it.
    private func send(_ text: String) async {
        for (id, writer) in clients {
            if await writer.write(text) == false {
                clients.removeValue(forKey: id)
            }
        }
        if clients.isEmpty { stopHeartbeat() }
    }

    /// Starts the heartbeat loop if it is not already running.
    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [heartbeat] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: heartbeat)
                } catch {
                    return
                }
                await self.send(SSEEvent.heartbeat)
            }
        }
    }

    /// Stops the heartbeat loop.
    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }
}
