//
//  ViewerEndpoints.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The viewer's data API: the routes every page and every other dashboard is built on.
///
/// ```text
/// GET /files                                  the dashboard's data
/// GET /files/{file}/tree.json                 ?node= ?depth= ?expand= ?props= ?theme=
/// GET /files/{file}/artboards/{artboard}.png  ?theme= ?max=
/// GET /files/{file}/artboards/{artboard}/export  ?format= ?scale= ?max= ?theme=
/// GET /files/{file}/activity.json             ?limit=
/// GET /events                                 Server-Sent Events
/// ```
///
/// They are documented for consumers in <doc:WoodcaseViewer>. The server registers a
/// page's routes *before* these, so at the same shape `ViewerPages` owns `/` and
/// `/files/{file}`; `{artboard}.png` is the narrower pattern and keeps the image
/// whatever a page registers beside it. The data routes are the page's source, not its
/// rival — one shape, one producer.
public enum ViewerEndpoints {
    /// The data routes.
    ///
    /// - Returns: The table to register after any page routes.
    public static func routes() -> ViewerRoutes {
        var routes = ViewerRoutes()
        routes.add(.get, "/files", handler: files)
        routes.add(.get, "/files/{file}/tree.json", handler: tree)
        routes.add(.get, "/files/{file}/artboards/{artboard}.png", handler: artboard)
        routes.add(.get, "/files/{file}/artboards/{artboard}/export", handler: export)
        routes.add(.get, "/files/{file}/activity.json", handler: activity)
        routes.add(.get, "/events", handler: events)
        return routes
    }

    /// `GET /files` — every file being served, with artboards and last change.
    ///
    /// The report is built by ``PageData/files(_:)``, which the dashboard page also
    /// calls: the endpoint and the page report the same thing because they are the same
    /// function, not because two implementations agree today.
    static func files(_ request: ViewerRequest) async throws -> HTTPResponse {
        try await .json(PageData.files(request.context))
    }

    /// `GET /files/{file}/tree.json` — the settled tree, in the tree verb's `--json` form.
    ///
    /// The body is ``TreeFormatter/json(_:revision:)`` verbatim: the same bytes
    /// `woodcase tree --json` prints, so the page's overlay and a script share one
    /// decoder. `?node=`, `?depth=`, `?expand=` and `?props=` mirror the verb's flags.
    static func tree(_ request: ViewerRequest) async throws -> HTTPResponse {
        let file = try await request.file()
        let theme = try request.theme()
        let depth = try request.integer("depth")
        let node = request.http.query["node"].flatMap { $0.isEmpty ? nil : $0 }
        let properties = (request.http.query["props"] ?? "")
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let expand = request.http.flag("expand")

        do {
            let json = try await PenFileTransaction.read(at: file.url, fonts: request.context.renders.fonts) { document in
                let rows = try TreeView.rows(
                    of: document,
                    root: node,
                    depth: depth,
                    expandInstances: expand,
                    theme: theme.isEmpty ? nil : theme,
                    properties: properties
                )
                return try TreeFormatter.json(rows, revision: document.documentRevision)
            }.value
            return .json(text: json)
        } catch let error as EditingError {
            throw ViewerError.unknownNode(
                address: node ?? "", file: file.id, reason: String(describing: error)
            )
        }
    }

    /// `GET /files/{file}/artboards/{artboard}.png` — one artboard, rendered.
    ///
    /// `?max=` caps the longer side in pixels the way `woodcase shot --max` does, and
    /// the scale it settled on comes back in `X-Woodcase-Scale` so a pixel coordinate
    /// can be mapped back to a layout point.
    static func artboard(_ request: ViewerRequest) async throws -> HTTPResponse {
        let file = try await request.file()
        let artboardID = request.parameters["artboard"] ?? ""
        let rendering = try await request.context.renders.png(
            artboard: artboardID,
            of: file,
            theme: request.theme(),
            longestSide: request.integer("max", minimum: 1)
        )

        var response = HTTPResponse.png(rendering.png)
        response.headers["X-Woodcase-Scale"] = String(rendering.scale)
        response.headers["X-Woodcase-Revision"] = rendering.revision
        response.headers["X-Woodcase-Width"] = String(rendering.artboard.width)
        response.headers["X-Woodcase-Height"] = String(rendering.artboard.height)
        return response
    }

    /// `GET /files/{file}/artboards/{artboard}/export` — one artboard as a download.
    ///
    /// `?format=` is one of ``ViewerExportFormat``, which is exactly what `render`,
    /// `shot` and `generate react` write and nothing else. `?scale=` is pixels per
    /// layout point and `?max=` is a cap on the longer side in points; `?max=` wins when
    /// both are given, and neither means anything to a PDF or to generated code.
    ///
    /// The response carries `Content-Disposition: attachment`, which is what turns a
    /// form submission into a saved file — the whole panel then needs no JavaScript.
    static func export(_ request: ViewerRequest) async throws -> HTTPResponse {
        let file = try await request.file()
        let artboardID = request.parameters["artboard"] ?? ""
        let raw = request.http.query["format"] ?? ViewerExportFormat.png.query
        guard let format = ViewerExportFormat(query: raw) else {
            throw ViewerError.unknownFormat(raw)
        }
        let theme = try request.theme()
        let prepared = try await request.context.renders.prepared(file, theme: theme)
        let artboard = try prepared.artboard(id: artboardID, of: file)

        let export = try await payload(
            format: format,
            artboard: artboard,
            file: file,
            theme: theme,
            size: size(from: request),
            context: request.context
        )
        return HTTPResponse(
            status: .ok,
            headers: [
                "Content-Type": export.mediaType,
                "Content-Disposition": "attachment; filename=\"\(export.filename)\"",
                "Cache-Control": "no-store",
            ],
            body: .data(export.data)
        )
    }

    /// How big a raster export should be, from `?scale=` and `?max=`.
    ///
    /// - Parameter request: The request to read.
    /// - Returns: The size, defaulting to 1× when the query says nothing.
    /// - Throws: ``ViewerError/malformedNumber(parameter:value:)``.
    static func size(from request: ViewerRequest) throws -> ArtboardExport.Size {
        if let edge = try request.integer("max", minimum: 1) {
            return .maximumEdge(edge)
        }
        return try .scale(Double(request.integer("scale", minimum: 1) ?? 1))
    }

    /// The bytes for one export, produced through the same render path the page uses.
    static func payload(
        format: ViewerExportFormat,
        artboard: Artboard,
        file: ViewerFile,
        theme: [String: String],
        size: ArtboardExport.Size,
        context: ViewerContext
    ) async throws -> ArtboardExport {
        switch format {
        case .png:
            let rendering = try await context.renders.image(
                artboard: artboard.id, of: file, theme: theme, scale: size.scale(for: artboard)
            )
            return ArtboardExport(
                data: rendering.png,
                mediaType: format.mediaType,
                filename: ArtboardExport.filename(
                    file: file.name,
                    artboard: artboard,
                    suffix: size.suffix(for: artboard),
                    extension: "png"
                )
            )
        case .pdf:
            return try await ArtboardExport(
                data: context.renders.pdf(artboard: artboard.id, of: file, theme: theme),
                mediaType: format.mediaType,
                filename: ArtboardExport.filename(
                    file: file.name, artboard: artboard, suffix: "", extension: "pdf"
                )
            )
        case let .code(target):
            let emission = try await context.renders.emission(file)
            guard let code = ArtboardCode.of(
                artboard: artboard.id, in: emission, target: target
            ) else {
                throw ViewerError.noGeneratedFile(artboard: artboard.id, target: target.rawValue)
            }
            return ArtboardExport(
                data: Data(code.text.utf8),
                mediaType: format.mediaType,
                filename: code.filename
            )
        }
    }

    /// `GET /files/{file}/activity.json` — the file's recent log events, oldest first.
    static func activity(_ request: ViewerRequest) async throws -> HTTPResponse {
        let file = try await request.file()
        let limit = try request.integer("limit", minimum: 1) ?? defaultActivityLimit
        let events = request.context.tail(count: limit, file: file.url)
        return try .json(ActivityReport(file: file.id, events: events))
    }

    /// `GET /events` — the Server-Sent Events stream.
    ///
    /// The response only opens the stream; the connection hands itself to the
    /// ``SSEHub``, which greets it with the current presence and then writes every
    /// `change` and `presence` event until the client leaves or the server stops.
    static func events(_ request: ViewerRequest) async throws -> HTTPResponse {
        _ = request
        return .eventStream()
    }

    /// How many activity events a request gets when it names no limit.
    static let defaultActivityLimit = 50
}
