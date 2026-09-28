//
//  ViewerRequest.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Everything a route handler is given: the request, what its pattern captured, and the
/// server's live state.
///
/// A handler is a pure function of this value — it holds no state of its own — so a page
/// component and a JSON endpoint are written the same way and tested the same way.
public struct ViewerRequest: Sendable {
    /// Creates a request for a handler.
    ///
    /// - Parameters:
    ///   - http: The parsed request.
    ///   - parameters: What the route's pattern captured.
    ///   - context: The server's caches, file index, log and event hub.
    public init(http: HTTPRequest, parameters: [String: String], context: ViewerContext) {
        self.http = http
        self.parameters = parameters
        self.context = context
    }

    /// The parsed request.
    public let http: HTTPRequest

    /// What the route's pattern captured, by parameter name.
    public let parameters: [String: String]

    /// The server's caches, file index, log and event hub.
    public let context: ViewerContext

    /// The file named by the `{file}` path parameter.
    ///
    /// - Returns: The file.
    /// - Throws: ``ViewerError/unknownFile(id:)`` when the id names no watched file —
    ///   the error carries the request that lists the ids that do exist.
    public func file() async throws -> ViewerFile {
        let id = parameters["file"] ?? ""
        guard let file = await context.files.file(id: id) else {
            throw ViewerError.unknownFile(id: id)
        }
        return file
    }

    /// The theme axes pinned by `?theme=`.
    ///
    /// - Returns: The pinned axes, empty when the query names none.
    /// - Throws: ``ViewerError/malformedTheme(_:)`` naming the pin that could not be read.
    public func theme() throws -> [String: String] {
        try ThemeQuery.parse(http.query["theme"])
    }

    /// An integer query parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter's name.
    ///   - minimum: The smallest value that makes sense for it.
    /// - Returns: The value, or `nil` when the query does not carry it.
    /// - Throws: ``ViewerError/malformedNumber(parameter:value:)`` when it is present
    ///   but is not a whole number at or above `minimum`.
    public func integer(_ name: String, minimum: Int = 0) throws -> Int? {
        guard let raw = http.query[name], !raw.isEmpty else { return nil }
        guard let value = Int(raw), value >= minimum else {
            throw ViewerError.malformedNumber(parameter: name, value: raw)
        }
        return value
    }
}
