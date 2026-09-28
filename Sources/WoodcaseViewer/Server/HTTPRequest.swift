//
//  HTTPRequest.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One parsed HTTP/1.1 request head.
///
/// The viewer serves reads only, so a request is its method, its path, its query and a
/// few headers — there is no body to speak of, and none is read. Parsing is deliberately
/// narrow: anything it does not understand is a typed ``ParseError`` the connection
/// answers with the right status, never a guess.
public struct HTTPRequest: Friendly {
    /// Creates a request.
    ///
    /// - Parameters:
    ///   - method: The request method.
    ///   - path: The percent-decoded path, without the query.
    ///   - query: The decoded query parameters.
    ///   - headers: The headers, with lowercased names.
    ///   - target: The raw request target, exactly as it arrived.
    public init(
        method: Method,
        path: String,
        query: [String: String],
        headers: [String: String],
        target: String
    ) {
        self.init(
            method: method,
            segments: path.split(separator: "/", omittingEmptySubsequences: true).map(String.init),
            query: query,
            headers: headers,
            target: target
        )
    }

    /// Creates a request from already-split path segments.
    ///
    /// - Parameters:
    ///   - method: The request method.
    ///   - segments: The path's segments, each already percent-decoded.
    ///   - query: The decoded query parameters.
    ///   - headers: The headers, with lowercased names.
    ///   - target: The raw request target, exactly as it arrived.
    public init(
        method: Method,
        segments: [String],
        query: [String: String],
        headers: [String: String],
        target: String
    ) {
        self.method = method
        self.segments = segments
        self.query = query
        self.headers = headers
        self.target = target
    }

    /// The methods the viewer serves.
    ///
    /// A read-only server has no use for the rest: a request naming one of them is
    /// answered `405 Method Not Allowed` rather than being half-understood.
    public enum Method: String, Friendly, CaseIterable {
        /// A read.
        case get = "GET"
        /// A read of the headers alone.
        case head = "HEAD"
    }

    /// Why a request head could not be parsed.
    public enum ParseError: Error, Friendly, CustomStringConvertible {
        /// The head was not a request line followed by header lines.
        case malformed
        /// The method is well-formed but not one this server answers.
        case unsupportedMethod(String)

        public var description: String {
            switch self {
            case .malformed:
                "The request head is not a well-formed HTTP/1.1 request."
            case let .unsupportedMethod(method):
                "The viewer is read-only and does not answer \(method); use GET or HEAD."
            }
        }
    }

    /// The request method.
    public let method: Method

    /// The path's segments, each percent-decoded on its own.
    ///
    /// Decoding per segment, rather than decoding the whole path and splitting it, is
    /// what lets an id containing a slash ride in one segment: an artboard inside an
    /// expanded component instance is `YGJ0d/nSNTs`, and it reaches this server as
    /// `/files/a1/artboards/YGJ0d%2FnSNTs.png` — one segment, not two.
    public let segments: [String]

    /// The decoded path, for reading and logging.
    ///
    /// Route matching uses ``segments``; this is the same thing joined back together,
    /// which is lossy exactly where a segment contained an encoded slash.
    public var path: String {
        "/" + segments.joined(separator: "/")
    }

    /// The decoded query parameters. A bare key (`?expand`) has an empty value.
    public let query: [String: String]

    /// The headers, with lowercased names.
    public let headers: [String: String]

    /// The raw request target, exactly as it arrived on the wire.
    public let target: String

    /// One header, matched without regard to case.
    ///
    /// - Parameter name: The header's name, in any case.
    /// - Returns: Its value, or `nil` if the request did not carry it.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// Whether a query flag is present, in either the bare (`?expand`) or the
    /// explicit (`?expand=1`) spelling.
    ///
    /// - Parameter name: The parameter's name.
    /// - Returns: `true` unless the parameter is absent or set to `0` or `false`.
    public func flag(_ name: String) -> Bool {
        guard let value = query[name] else { return false }
        return !["0", "false", "no"].contains(value.lowercased())
    }

    // MARK: - Parsing

    /// The length of the request head in a buffer, or `nil` while it is still arriving.
    ///
    /// A head ends at the first blank line. Until one has arrived the connection must
    /// keep reading rather than parse a fragment.
    ///
    /// - Parameter data: Everything read from the connection so far.
    /// - Returns: The number of bytes before the blank line, or `nil` if there is none.
    public static func headLength(in data: Data) -> Int? {
        let terminator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: terminator) else { return nil }
        return data.distance(from: data.startIndex, to: range.lowerBound)
    }

    /// Parses a request head.
    ///
    /// - Parameter head: The head's text, with or without its trailing blank line.
    /// - Returns: The parsed request.
    /// - Throws: ``ParseError`` naming what was wrong with it.
    public static func parse(head: String) throws -> HTTPRequest {
        let lines = head
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw ParseError.malformed
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw ParseError.malformed }
        let verb = String(parts[0])
        guard let method = Method(rawValue: verb) else {
            throw ParseError.unsupportedMethod(verb)
        }

        let target = String(parts[1])
        guard target.hasPrefix("/") else { throw ParseError.malformed }
        let (rawPath, rawQuery) = split(target: target)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex ..< colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequest(
            method: method,
            segments: rawPath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map { decode(String($0)) },
            query: parseQuery(rawQuery),
            headers: headers,
            target: target
        )
    }

    /// Splits a request target into its path and its raw query string.
    private static func split(target: String) -> (path: String, query: String) {
        guard let mark = target.firstIndex(of: "?") else { return (target, "") }
        return (String(target[target.startIndex ..< mark]), String(target[target.index(after: mark)...]))
    }

    /// Decodes a raw query string into parameters, last spelling of a repeated key winning.
    private static func parseQuery(_ raw: String) -> [String: String] {
        guard !raw.isEmpty else { return [:] }
        var query: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
            guard let equals = pair.firstIndex(of: "=") else {
                query[decode(String(pair), plusIsSpace: true)] = ""
                continue
            }
            let name = decode(String(pair[pair.startIndex ..< equals]), plusIsSpace: true)
            let value = decode(String(pair[pair.index(after: equals)...]), plusIsSpace: true)
            query[name] = value
        }
        return query
    }

    /// Percent-decodes one component, optionally reading `+` as a space.
    ///
    /// `+` means a space in a query string and nothing special in a path, which is why
    /// the two callers ask for different treatment.
    private static func decode(_ text: String, plusIsSpace: Bool = false) -> String {
        let prepared = plusIsSpace ? text.replacingOccurrences(of: "+", with: " ") : text
        return prepared.removingPercentEncoding ?? prepared
    }
}
