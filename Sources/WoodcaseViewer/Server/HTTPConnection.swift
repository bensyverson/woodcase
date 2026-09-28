//
//  HTTPConnection.swift
//  WoodcaseViewer
//

import Dispatch
import Foundation
import Network

/// One accepted TCP connection, from its first byte to its last.
///
/// It reads until the request head is complete, matches it, calls the handler, writes
/// the answer, and closes — no keep-alive, because a viewer serves a handful of requests
/// per page and a connection per request is one fewer state machine to get wrong.
///
/// The exception is `/events`: an event-stream response is *not* followed by a close.
/// The connection hands itself to the ``SSEHub`` as an ``SSEWriter`` and stays open,
/// which is what makes the stream a stream.
@available(macOS 15, iOS 18, *)
actor HTTPConnection {
    /// Creates a connection handler.
    ///
    /// - Parameters:
    ///   - connection: The accepted connection.
    ///   - routes: The table to match against.
    ///   - context: The server state handlers work from.
    ///   - queue: The queue Network callbacks run on.
    init(
        connection: NWConnection,
        routes: ViewerRoutes,
        context: ViewerContext,
        queue: DispatchQueue
    ) {
        self.connection = connection
        self.routes = routes
        self.context = context
        self.queue = queue
    }

    /// The largest request head this server will read.
    ///
    /// A head is a request line and a few short headers. Anything past this is not a
    /// browser being verbose, it is something the viewer should not be trying to parse.
    static let maximumHeadBytes = 64 * 1024

    /// How long a write waits to be handed to the transport before the client is given up on.
    ///
    /// `contentProcessed` fires when the bytes reach the protocol stack, which on
    /// loopback is immediate — unless the peer has stopped reading and the send window
    /// has filled, and then it may never fire at all. See ``ResumeOnce/budget``.
    static let sendBudget: Duration = ResumeOnce<Bool>.budget

    /// Says on stderr that a write was abandoned, and why.
    ///
    /// A give-up is silent otherwise — the client is simply dropped — and silence is what
    /// made this class of failure expensive to diagnose: before the budget existed, a
    /// write nobody took stopped a whole test run with no frame of ours in the sample to
    /// explain it. It costs one line, and only on a stall that should never happen.
    ///
    /// - Parameter what: What was being written.
    static func gaveUp(on what: String) {
        let note = "woodcase viewer: gave up on \(what) after \(sendBudget); dropping the client.\n"
        FileHandle.standardError.write(Data(note.utf8))
    }

    private let connection: NWConnection
    private let routes: ViewerRoutes
    private let context: ViewerContext
    private let queue: DispatchQueue

    /// What has arrived and not yet been parsed.
    private var buffer = Data()

    /// Whether the connection has been handed to the SSE hub and must not be closed.
    private var isStreaming = false

    /// Starts the connection and reads its request.
    func start() {
        connection.start(queue: queue)
        receive()
    }

    // MARK: - Reading

    /// Reads the next chunk, parsing once the head is complete.
    ///
    /// The handler captures `self` **strongly**, on purpose: nothing else holds this
    /// actor between the accept and the answer, and a weak capture makes every request
    /// time out — the actor is gone before the first byte arrives. The cycle is broken
    /// by the read itself, which happens exactly once per armed receive and then
    /// releases the closure.
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumHeadBytes) {
            data, _, isComplete, error in
            Task { await self.received(data, isComplete: isComplete, failed: error != nil) }
        }
    }

    /// Handles one chunk.
    private func received(_ data: Data?, isComplete: Bool, failed: Bool) async {
        if let data { buffer.append(data) }

        if let length = HTTPRequest.headLength(in: buffer) {
            let head = String(decoding: buffer.prefix(length), as: UTF8.self)
            await respond(to: head)
            return
        }
        if failed || isComplete || buffer.count >= Self.maximumHeadBytes {
            // Either the client went away mid-head, or it sent more head than a request
            // can reasonably be. Neither is answerable.
            close()
            return
        }
        receive()
    }

    // MARK: - Answering

    /// Parses a head, runs its handler, and writes the answer.
    private func respond(to head: String) async {
        let request: HTTPRequest
        do {
            request = try HTTPRequest.parse(head: head)
        } catch let error as HTTPRequest.ParseError {
            await write(Self.response(for: error))
            return
        } catch {
            await write(.failure(
                .badRequest,
                message: "The request could not be read.",
                remedy: "Send a well-formed HTTP/1.1 GET."
            ))
            return
        }

        switch routes.match(request) {
        case let .handler(handler, parameters):
            let viewerRequest = ViewerRequest(
                http: request, parameters: parameters, context: context
            )
            do {
                try await write(handler(viewerRequest), for: request)
            } catch let error as ViewerError {
                await write(error.response())
            } catch {
                await write(.failure(
                    .internalServerError,
                    message: "\(request.path) failed: \(error)",
                    remedy: "Check the file with `woodcase lint`, then retry the request."
                ))
            }
        case let .methodNotAllowed(allowed):
            var response = HTTPResponse.failure(
                .methodNotAllowed,
                message: "\(request.path) does not answer \(request.method.rawValue).",
                remedy: "Use \(allowed.map(\.rawValue).sorted().joined(separator: " or "))."
            )
            response.headers["Allow"] = allowed.map(\.rawValue).sorted().joined(separator: ", ")
            await write(response)
        case .notFound:
            await write(.failure(
                .notFound,
                message: "Nothing is served at \(request.path).",
                remedy: "GET / lists the endpoints this server answers."
            ))
        }
    }

    /// The answer to a head that could not be parsed.
    private static func response(for error: HTTPRequest.ParseError) -> HTTPResponse {
        switch error {
        case .malformed:
            return .failure(
                .badRequest,
                message: error.description,
                remedy: "Send a well-formed HTTP/1.1 GET."
            )
        case .unsupportedMethod:
            var response = HTTPResponse.failure(
                .methodNotAllowed,
                message: error.description,
                remedy: "The viewer is read-only; use GET."
            )
            response.headers["Allow"] = "GET, HEAD"
            return response
        }
    }

    // MARK: - Writing

    /// Writes a response, then either closes or begins streaming.
    private func write(_ response: HTTPResponse, for request: HTTPRequest? = nil) async {
        // A head that never reached the client is the end of this exchange: there is
        // nobody to send a body to, and an event stream handed to the hub would be a
        // client it writes into forever.
        guard await send(response.headData()) else {
            close()
            return
        }

        switch response.body {
        case let .data(payload):
            // HEAD gets the head and nothing else, which is the whole point of it.
            if request?.method != .head, !payload.isEmpty {
                _ = await send(payload)
            }
            close()
        case .eventStream:
            isStreaming = true
            await context.events.add(
                NetworkSSEWriter(connection: connection, queue: queue)
            )
        }
    }

    /// Sends bytes, waiting for them to be handed to the network.
    ///
    /// - Parameter data: The bytes to write.
    /// - Returns: `false` if the client did not take them, including when it stopped
    ///   taking them altogether — the connection is cancelled in that case, because a
    ///   peer that has not read a byte in ``sendBudget`` is not coming back.
    private func send(_ data: Data) async -> Bool {
        await ResumeOnce.value(
            within: Self.sendBudget,
            on: queue,
            expiring: { [connection] in
                Self.gaveUp(on: "a response the client stopped reading")
                connection.cancel()
                return false
            }
        ) { [connection] box in
            connection.send(content: data, completion: .contentProcessed { error in
                box.resume(with: error == nil)
            })
        }
    }

    /// Closes the connection unless it has become a stream.
    private func close() {
        guard !isStreaming else { return }
        connection.cancel()
    }
}

/// Writes an event stream to a live connection, one HTTP chunk per event.
///
/// The whole of what the ``SSEHub`` needs to know about Network.framework — plus the
/// chunk framing, which belongs here and not in the hub: an event is a piece of the
/// viewer's API, a chunk is a detail of how HTTP/1.1 delimits one.
///
/// Its writes are bounded, and that matters more here than anywhere else in the server:
/// the hub broadcasts to its clients one at a time from inside its own actor, so a single
/// stream that stopped taking bytes would hold the hub — and every `stop()` waiting to
/// close it — for as long as the process lived.
@available(macOS 15, iOS 18, *)
struct NetworkSSEWriter: SSEWriter {
    /// The connection to write to.
    let connection: NWConnection

    /// The queue this connection's callbacks and write deadlines run on.
    let queue: DispatchQueue

    func write(_ text: String) async -> Bool {
        let payload = Data(text.utf8)
        guard !payload.isEmpty else { return true }
        var chunk = Data("\(String(payload.count, radix: 16))\r\n".utf8)
        chunk.append(payload)
        chunk.append(Data("\r\n".utf8))
        return await send(chunk)
    }

    func close() async {
        // The zero-length chunk is what tells the client the stream ended rather than
        // broke, so a page can distinguish "the server stopped" from "the wifi did".
        _ = await send(Data("0\r\n\r\n".utf8))
        connection.cancel()
    }

    /// Sends bytes, reporting whether the client is still there.
    ///
    /// - Parameter data: The chunk to write.
    /// - Returns: `false` if the client is gone or has stopped reading, which is the
    ///   hub's signal to drop it.
    private func send(_ data: Data) async -> Bool {
        await ResumeOnce.value(
            within: HTTPConnection.sendBudget,
            on: queue,
            expiring: {
                HTTPConnection.gaveUp(on: "an event stream the client stopped reading")
                connection.cancel()
                return false
            }
        ) { box in
            connection.send(content: data, completion: .contentProcessed { error in
                box.resume(with: error == nil)
            })
        }
    }
}
