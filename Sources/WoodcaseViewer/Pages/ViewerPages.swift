//
//  ViewerPages.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The viewer page's route table — what `ViewerServer(pages:)` is handed.
///
/// ```swift
/// let server = ViewerServer(pages: { _ in ViewerPages.routes() })
/// ```
///
/// Four pages, nine fragments, three preview routes (plus the fixture files' artboard
/// images, drawn by ``PreviewFixtures/render``), two assets — pages only. The
/// preview routes are here rather than in a table of their own so `woodcase serve`
/// carries them: a person already looking at a document should not have to start a
/// second process to check a component. Each page route returns the
/// *whole* page from its page component, so it is correct with the script switched off;
/// each fragment returns one component of that same composition, which is what a live
/// update swaps in. No data route is registered here: `/files/{file}/artboards/{artboard}`
/// sits beside the ``ViewerEndpoints`` `.png` route and loses to it on specificity, so
/// the image keeps one producer without this table claiming it.
///
/// `/files/{file}/artboards` and `/files/{file}/artboards/{artboard}` are two different
/// answers rather than a listing and its members: the first is the map page's outline
/// fragment, the second is a whole page. Specificity keeps them apart — a two-segment
/// pattern never matches a three-segment path.
public enum ViewerPages {
    /// The table to hand ``ViewerServer/init(pages:)``.
    ///
    /// - Returns: The page routes. They are registered ahead of the data endpoints, which
    ///   only decides ties — see ``ViewerRoutes/match(_:)``.
    public static func routes() -> ViewerRoutes {
        var routes = ViewerRoutes()

        routes.add(.get, "/", handler: dashboard)
        routes.add(.get, "/files/{file}", handler: artboard)
        routes.add(.get, "/files/{file}/artboards/{artboard}", handler: artboard)

        routes.add(.get, "/files/{file}/activity") { try await .html(ArtboardPageBuilder.activity($0)) }
        routes.add(.get, "/files/{file}/variables") { try await .html(ArtboardPageBuilder.variables($0)) }
        routes.add(.get, "/files/{file}/details") { try await .html(ArtboardPageBuilder.details($0)) }
        routes.add(.get, "/files/{file}/presence") { await .html(ArtboardPageBuilder.presence($0)) }
        routes.add(.get, "/files/{file}/map") { try await .html(ArtboardPageBuilder.map($0)) }
        routes.add(.get, "/files/{file}/artboards") { try await .html(ArtboardPageBuilder.artboards($0)) }
        routes.add(.get, "/files/{file}/follow") { try await .html(ArtboardPageBuilder.follow($0)) }
        routes.add(.get, "/files/{file}/artboards/{artboard}/outline") {
            try await .html(ArtboardPageBuilder.outline($0))
        }
        routes.add(.get, "/files/{file}/artboards/{artboard}/follow") {
            try await .html(ArtboardPageBuilder.follow($0))
        }
        routes.add(.get, "/files/{file}/artboards/{artboard}/render") {
            try await .html(ArtboardPageBuilder.render($0))
        }
        routes.add(.get, "/files/{file}/artboards/{artboard}/code") {
            try await .html(ArtboardPageBuilder.code($0))
        }

        routes.add(.get, ViewerLink.previews, handler: previewIndex)
        routes.add(.get, "\(ViewerLink.previews)/{component}", handler: previewCanvas)
        routes.add(.get, "\(ViewerLink.previews)/{component}/{state}", handler: previewState)
        // The fixture files' artboards, which no host serves, drawn from the catalog. A
        // literal file segment outranks the `{file}` capture of the real image route, so
        // `serve` answers these the same way `preview` does and a real file keeps its own.
        for file in PreviewFixtures.fileIDs {
            routes.add(.get, "/files/\(file)/artboards/{artboard}.png") { _ in
                .png(PreviewFixtures.render)
            }
        }

        routes.add(.get, ViewerLink.stylesheet) { _ in
            asset(ViewerStylesheet.css, type: "text/css; charset=utf-8")
        }
        routes.add(.get, ViewerLink.script) { _ in
            asset(ViewerScript.javaScript, type: "text/javascript; charset=utf-8")
        }
        return routes
    }

    /// A text asset compiled into the binary.
    ///
    /// The stylesheet and the script are Swift strings, not files: `woodcase serve` is
    /// one executable, and a viewer that had to find its own assets on disk would be one
    /// more thing to get wrong when the binary moves.
    ///
    /// - Parameters:
    ///   - text: The asset's text.
    ///   - type: Its content type.
    /// - Returns: The response, uncached — the asset changes when the binary does, and a
    ///   stale stylesheet after an upgrade is a bad afternoon.
    static func asset(_ text: String, type: String) -> HTTPResponse {
        HTTPResponse(
            status: .ok,
            headers: ["Content-Type": type, "Cache-Control": "no-store"],
            body: .data(Data(text.utf8))
        )
    }

    /// `GET /` — the dashboard, or the empty state when nothing is being served.
    static func dashboard(_ request: ViewerRequest) async throws -> HTTPResponse {
        let context = request.context
        let clock = ViewerClock()
        let report = await PageData.files(context)
        let events = PageData.events(context, limit: 20)

        guard !report.files.isEmpty else {
            return .html(EmptyPage(
                logPath: PageData.logPath(context),
                eventCount: events.count,
                clock: clock
            ).render())
        }
        return await .html(DashboardPage(
            files: report.files,
            events: events,
            presence: PageData.presence(context),
            clock: clock,
            logPath: PageData.logPath(context)
        ).render())
    }

    /// `GET /files/{file}` — the map, or the artboard — and
    /// `GET /files/{file}/artboards/{artboard}`, which is always the artboard.
    static func artboard(_ request: ViewerRequest) async throws -> HTTPResponse {
        try await .html(ArtboardPageBuilder.page(request))
    }

    /// `GET /preview` — the catalog's index.
    ///
    /// The three preview handlers read ``PreviewCatalog/all`` and nothing else: no
    /// file, no log, no render cache. That is what lets `woodcase preview` answer them
    /// over an empty context and `woodcase serve` answer them with the identical bytes
    /// beside a live document — one host, not two.
    static func previewIndex(_: ViewerRequest) -> HTTPResponse {
        .html(PreviewIndex(components: PreviewCatalog.all, clock: ViewerClock()).render())
    }

    /// `GET /preview/{component}` — every state of one component, stacked.
    static func previewCanvas(_ request: ViewerRequest) throws -> HTTPResponse {
        let component = try component(request)
        return .html(PreviewCanvas(component: component, clock: ViewerClock()).render())
    }

    /// `GET /preview/{component}/{state}` — one state, alone.
    ///
    /// A ``PreviewFrame/page`` state is answered with its own markup and nothing else:
    /// it is already a whole ``ViewerDocument``, and wrapping it in a second one would
    /// nest two `<body>` elements. Every other frame is wrapped in
    /// ``PreviewStatePage``, which gives it the surface it declares.
    static func previewState(_ request: ViewerRequest) throws -> HTTPResponse {
        let component = try component(request)
        let slug = request.parameters["state"] ?? ""
        guard let state = component.state(slug: slug) else {
            throw ViewerError.unknownPreviewState(
                component: component.slug, slug: slug, available: component.states.map(\.slug)
            )
        }
        guard state.frame != .page else {
            return .html(state.render())
        }
        return .html(
            PreviewStatePage(component: component, state: state, clock: ViewerClock()).render()
        )
    }

    /// The component named by the `{component}` path parameter.
    ///
    /// - Parameter request: The request, carrying the captured slug.
    /// - Returns: The component.
    /// - Throws: ``ViewerError/unknownPreviewComponent(slug:available:)``, whose body
    ///   lists every slug the catalog does have.
    private static func component(_ request: ViewerRequest) throws -> PreviewComponent {
        let slug = request.parameters["component"] ?? ""
        guard let component = PreviewCatalog.component(slug: slug) else {
            throw ViewerError.unknownPreviewComponent(
                slug: slug, available: PreviewCatalog.all.map(\.slug)
            )
        }
        return component
    }
}
