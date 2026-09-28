//
//  ViewerRoutes.swift
//  WoodcaseViewer
//

import Foundation

/// The viewer's route table: the seam a page adds itself through.
///
/// The server knows nothing about pages. It is handed a `ViewerRoutes`, matches each
/// request against it, and calls whatever handler comes back. So a page — HTML, a
/// fragment, a stylesheet — is added without touching `Server/`:
///
/// ```swift
/// var pages = ViewerRoutes()
/// pages.add(.get, "/") { request in
///     .html(DashboardPage(files: await request.context.files.files).render())
/// }
/// pages.add(.get, "/files/{file}/outline") { request in
///     .html(OutlinePanel(rows: try await request.rows()).render())
/// }
/// let server = ViewerServer(pages: { _ in pages })
/// ```
///
/// ## Precedence is specificity, then registration order
///
/// The most specific route that matches wins — a literal segment beats a capture with a
/// suffix, which beats a bare capture — so a page at
/// `/files/{file}/artboards/{artboard}` cannot swallow the `.png` endpoint beside it,
/// whichever went in first. Only when two patterns are the same shape does order decide,
/// and the server registers a page's routes before its own: that is what lets a page take
/// over `/` and `/files/{file}` from the placeholders without removing anything, and it
/// is why `add(contentsOf:)` appends.
public struct ViewerRoutes: Sendable {
    /// What a route does with a request.
    public typealias Handler = @Sendable (ViewerRequest) async throws -> HTTPResponse

    /// An empty table.
    public init() {}

    /// What matching a request produced.
    ///
    /// The three cases are three different answers — a handler, `405` with the methods
    /// that would work, or `404`. A table that could not tell the last two apart would
    /// make a `POST` to a real path look like a typo.
    public enum Resolution: Sendable {
        /// A route matched; call this handler with these captured parameters.
        case handler(Handler, parameters: [String: String])
        /// This path exists, but not for this method.
        case methodNotAllowed(allowed: Set<HTTPRequest.Method>)
        /// No route claims this path.
        case notFound
    }

    /// One entry: a route and what it does.
    private struct Entry {
        let route: Route
        let handler: Handler
    }

    /// The entries, in registration order.
    private var entries: [Entry] = []

    /// The routes in the table, in registration order.
    public var routes: [Route] {
        entries.map(\.route)
    }

    /// Adds a route.
    ///
    /// - Parameters:
    ///   - method: The method it answers. A `.get` route answers `HEAD` as well.
    ///   - pattern: The path pattern — see ``Route``.
    ///   - handler: What to do with a matching request.
    public mutating func add(
        _ method: HTTPRequest.Method,
        _ pattern: String,
        handler: @escaping Handler
    ) {
        entries.append(Entry(route: Route(method, pattern), handler: handler))
    }

    /// Appends another table's routes after this one's.
    ///
    /// - Parameter other: The table to append. Its routes win only where they are more
    ///   specific than this one's; at the same shape this table's route answers, which is
    ///   how the server lets a page shadow a built-in route.
    public mutating func add(contentsOf other: ViewerRoutes) {
        entries.append(contentsOf: other.entries)
    }

    /// Matches a request.
    ///
    /// Every entry is tried, and the most specific route that answers this method wins;
    /// at equal ``Route/specificity`` the one registered first does. Entries that match
    /// the path under another method are what the `405` reports.
    ///
    /// - Parameter request: The parsed request.
    /// - Returns: The handler and its parameters, the methods this path does answer, or
    ///   ``Resolution/notFound``.
    public func match(_ request: HTTPRequest) -> Resolution {
        var allowed: Set<HTTPRequest.Method> = []
        var best: (entry: Entry, parameters: [String: String])?

        for entry in entries {
            guard let parameters = entry.route.match(segments: request.segments) else { continue }
            // A GET route answers HEAD too: the connection writes the head and stops,
            // so a probe never gets a 405 for asking politely.
            guard entry.route.method == request.method
                || (entry.route.method == .get && request.method == .head)
            else {
                allowed.insert(entry.route.method)
                continue
            }
            // Strictly greater, so an equally specific route registered earlier keeps it.
            if best.map({ entry.route.specificity > $0.entry.route.specificity }) ?? true {
                best = (entry, parameters)
            }
        }

        if let best {
            return .handler(best.entry.handler, parameters: best.parameters)
        }
        return allowed.isEmpty ? .notFound : .methodNotAllowed(allowed: allowed)
    }
}
