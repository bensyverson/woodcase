//
//  SSEHubTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

@Suite(.hangGuard)
struct SSEHubTests {
    /// A client that keeps what it was written, and can refuse to accept more.
    private actor Client: SSEWriter {
        private(set) var writes: [String] = []
        private(set) var isClosed = false
        private var accepts = true

        init(accepts: Bool = true) {
            self.accepts = accepts
        }

        func write(_ text: String) async -> Bool {
            guard accepts else { return false }
            writes.append(text)
            return true
        }

        func close() async {
            isClosed = true
        }

        var count: Int {
            writes.count
        }

        func contains(_ text: String) -> Bool {
            writes.contains { $0.contains(text) }
        }
    }

    private struct Payload: Codable, Equatable { let value: Int }

    @Test("A broadcast reaches every connected client")
    func broadcastsToAll() async throws {
        let hub = SSEHub()
        let first = Client()
        let second = Client()
        await hub.add(first)
        await hub.add(second)

        try await hub.broadcast(.change, payload: Payload(value: 1))

        #expect(await first.contains("event: change"))
        #expect(await second.contains("\"value\" : 1"))
        #expect(await hub.clientCount == 2)
    }

    @Test("Event ids increase, so a client can say where it left off")
    func idsIncrease() async throws {
        let hub = SSEHub()
        let client = Client()
        await hub.add(client)

        try await hub.broadcast(.change, payload: Payload(value: 1))
        try await hub.broadcast(.presence, payload: Payload(value: 2))

        #expect(await client.contains("id: 1\nevent: change"))
        #expect(await client.contains("id: 2\nevent: presence"))
        #expect(await hub.lastEvent == 2)
    }

    @Test("A client whose write fails is dropped rather than written to forever")
    func dropsDeadClients() async throws {
        let hub = SSEHub()
        await hub.add(Client(accepts: false))
        #expect(await hub.clientCount == 1)

        try await hub.broadcast(.change, payload: Payload(value: 1))

        #expect(await hub.clientCount == 0)
    }

    @Test("A new client is greeted before it sees any live event")
    func greetsNewClients() async {
        let hub = SSEHub()
        await hub.setGreeting {
            [SSEEvent(id: 0, name: .presence, data: "{\"hello\":true}")]
        }
        let client = Client()
        await hub.add(client)

        #expect(await client.count == 1)
        #expect(await client.contains("{\"hello\":true}"))
    }

    @Test("Closing closes every client and empties the hub, so nothing outlives stop()")
    func closeAllTerminates() async {
        let hub = SSEHub()
        let client = Client()
        await hub.add(client)

        await hub.closeAll()

        #expect(await client.isClosed)
        #expect(await hub.clientCount == 0)
    }

    @Test("An idle stream gets a heartbeat comment, so it is not mistaken for a dead one")
    func sendsHeartbeats() async {
        let hub = SSEHub(heartbeat: .milliseconds(50))
        let client = Client()
        await hub.add(client)
        defer { Task { await hub.closeAll() } }

        await waitUntil("a heartbeat") { await client.contains(": heartbeat") }
    }
}
