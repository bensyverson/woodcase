//
//  HTTPResponse.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One HTTP/1.1 response: a status, some headers, and either a body or an open stream.
///
/// A handler builds one of these and is done; the connection serializes it. The body is
/// a typed choice rather than a flag, because "this response has no length and never
/// ends" is a different kind of thing from "here are the bytes", and the connection has
/// to treat them differently — a stream is handed to the ``SSEHub`` and stays open.
public struct HTTPResponse: Sendable {
    /// Creates a response.
    ///
    /// - Parameters:
    ///   - status: The status to send.
    ///   - headers: Headers to send, beyond the ones the serializer always writes.
    ///   - body: The bytes to send, or the marker for an event stream.
    public init(status: Status = .ok, headers: [String: String] = [:], body: Body) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// The statuses the viewer sends.
    public enum Status: Int, Friendly {
        /// The request was served.
        case ok = 200
        /// The request itself was wrong — a bad query parameter, a malformed head.
        case badRequest = 400
        /// Nothing is served at this path.
        case notFound = 404
        /// This path exists, but not for this method.
        case methodNotAllowed = 405
        /// The server failed while producing the answer.
        case internalServerError = 500

        /// The reason phrase the status code is known by.
        public var reason: String {
            switch self {
            case .ok: "OK"
            case .badRequest: "Bad Request"
            case .notFound: "Not Found"
            case .methodNotAllowed: "Method Not Allowed"
            case .internalServerError: "Internal Server Error"
            }
        }
    }

    /// What follows the head.
    public enum Body: Sendable {
        /// A complete body of this many bytes; the connection closes after sending it.
        case data(Data)
        /// An open `text/event-stream`; the connection is handed to the ``SSEHub``.
        case eventStream
    }

    /// The status to send.
    public var status: Status

    /// Headers to send beyond the ones the serializer always writes.
    public var headers: [String: String]

    /// The bytes to send, or the marker for an event stream.
    public var body: Body

    // MARK: - Builders

    /// An HTML page.
    ///
    /// - Parameters:
    ///   - html: The markup.
    ///   - status: The status to send it with.
    /// - Returns: The response.
    public static func html(_ html: String, status: Status = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .data(Data(html.utf8))
        )
    }

    /// A body of JSON text that has already been rendered — the tree report, for one,
    /// which must be byte-identical to what `woodcase tree --json` prints.
    ///
    /// - Parameters:
    ///   - json: The JSON text.
    ///   - status: The status to send it with.
    /// - Returns: The response.
    public static func json(text json: String, status: Status = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: .data(Data(json.utf8))
        )
    }

    /// A JSON body encoded from a value, with sorted keys so the bytes are stable.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - status: The status to send it with.
    /// - Returns: The response.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot encode.
    public static func json(_ value: some Encodable, status: Status = .ok) throws -> HTTPResponse {
        try HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: .data(ViewerJSON.encoder.encode(value))
        )
    }

    /// A PNG image.
    ///
    /// - Parameter png: The image's bytes.
    /// - Returns: The response.
    public static func png(_ png: Data) -> HTTPResponse {
        HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "image/png", "Cache-Control": "no-store"],
            body: .data(png)
        )
    }

    /// An open Server-Sent Events stream.
    ///
    /// - Returns: The response; the connection stays open once its head is written.
    public static func eventStream() -> HTTPResponse {
        HTTPResponse(
            status: .ok,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                // An HTTP/1.1 body with neither a length nor chunking is delimited by
                // the connection closing — so a client is entitled to buffer the whole
                // thing until then, which is the opposite of a live stream. Each event
                // goes out as one chunk; the writer does the framing.
                "Transfer-Encoding": "chunked",
                // Nothing sits in front of this server today, but a reverse proxy that
                // buffers a stream turns live updates into a long silence.
                "X-Accel-Buffering": "no",
            ],
            body: .eventStream
        )
    }

    /// A failure that says what happened and what to do next.
    ///
    /// - Parameters:
    ///   - status: The status to send.
    ///   - message: What went wrong, naming the thing by its id or path.
    ///   - remedy: The next request that would work.
    /// - Returns: The response, as JSON, so a script reads the same words a human does.
    public static func failure(
        _ status: Status,
        message: String,
        remedy: String
    ) -> HTTPResponse {
        let report = ViewerFailure(error: message, remedy: remedy, status: status.rawValue)
        // The encoder cannot fail on three strings, but a failure path must not throw
        // a second time: fall back to the plainest possible body.
        guard let response = try? json(report, status: status) else {
            return HTTPResponse(
                status: status,
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: .data(Data("\(message)\n\(remedy)\n".utf8))
            )
        }
        return response
    }

    // MARK: - The wire

    /// The status line and headers, ending in the blank line that closes the head.
    ///
    /// A `.data` body's `Content-Length` and `Connection: close` are written here; an
    /// event stream gets neither, because it has no length and does not close.
    ///
    /// - Returns: The head's bytes.
    public func headData() -> Data {
        var lines = ["HTTP/1.1 \(status.rawValue) \(status.reason)"]
        var all = headers
        switch body {
        case let .data(payload):
            all["Content-Length"] = String(payload.count)
            all["Connection"] = "close"
        case .eventStream:
            break
        }
        for name in all.keys.sorted() {
            lines.append("\(name): \(all[name] ?? "")")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}

/// The JSON body of a failed request: what happened, and the request that would work.
struct ViewerFailure: Friendly {
    /// What went wrong, naming the thing by its id or path.
    let error: String
    /// The next request to try.
    let remedy: String
    /// The HTTP status, repeated in the body so a logged response explains itself.
    let status: Int
}
