//
//  RenderCache.swift
//  WoodcaseViewer
//

import CoreGraphics
import Foundation
import Woodcase

/// The viewer's warm pipeline: prepared documents and rendered PNGs, held until the
/// file they came from changes.
///
/// Two caches, because they are invalidated by the same thing but cost very different
/// amounts. Preparing a document — expand, resolve, register fonts, lay out — is the
/// expensive half and depends only on the file and the theme; rendering an artboard to
/// PNG is the cheap half and depends on the artboard and the size as well. A viewer
/// clicking through artboards of one file pays the expensive half once.
///
/// Everything here runs on the actor's own executor, never the main actor: only the
/// parse itself touches ``EditableDocument``, and it does that inside a
/// ``PenFileTransaction/read(at:timeout:diagnostics:fonts:isolation:_:)`` whose body is hopped onto the main actor
/// and back. Renders of different files therefore serialize behind this actor, which is
/// what stops two SSE-driven refreshes rendering the same artboard twice.
public actor RenderCache {
    /// Creates an empty cache.
    ///
    /// - Parameters:
    ///   - maximumScale: The most a render is ever scaled up. Two matches
    ///     `woodcase render`'s default and is the point past which a design tool's
    ///     screenshot stops telling you anything new.
    ///   - defaultLongestSide: The pixel cap applied when a request names none, matching
    ///     `woodcase shot --max`.
    ///   - fonts: Where a document's Google Fonts are downloaded and registered from.
    ///     The process-wide ``GoogleFontResolver/shared`` in production, which is what a
    ///     served viewer wants: a designer's file names faces this machine may not have,
    ///     and the viewer is a rendering surface, so it fetches them the way `shot` does.
    ///     A test passes a resolver over a temporary cache and a fetcher that answers
    ///     from fixtures — see the same parameter on ``SettledTree``.
    ///   - images: Where remote image fills are downloaded from, on the same terms.
    public init(
        maximumScale: Double = 2,
        defaultLongestSide: Int = 1600,
        fonts: GoogleFontResolver = .shared,
        images: RemoteImageResolver = .shared
    ) {
        self.maximumScale = maximumScale
        self.defaultLongestSide = defaultLongestSide
        self.fonts = fonts
        self.images = images
    }

    /// What identifies one rendered image.
    public struct Key: Friendly {
        /// The file's ``ViewerFile/id``.
        public let file: String
        /// The artboard's node id.
        public let artboard: String
        /// The theme selection, in ``ThemeQuery/canonical(_:)`` form.
        public let theme: String
        /// The pixel cap on the longest side.
        public let longestSide: Int
    }

    /// A rendered artboard: the PNG, and how to map its pixels back to layout points.
    public struct Rendering: Sendable {
        /// Creates a rendering.
        ///
        /// - Parameters:
        ///   - png: The image's PNG bytes.
        ///   - scale: Pixels per layout point.
        ///   - artboard: The artboard that was rendered.
        ///   - revision: The document revision it was rendered from.
        public init(png: Data, scale: Double, artboard: Artboard, revision: String) {
            self.png = png
            self.scale = scale
            self.artboard = artboard
            self.revision = revision
        }

        /// The image's PNG bytes.
        public let png: Data
        /// Pixels per layout point — divide a pixel coordinate by this to get a
        /// layout coordinate, which is what an overlay needs.
        public let scale: Double
        /// The artboard that was rendered, with its settled size in points.
        public let artboard: Artboard
        /// The document revision it was rendered from.
        public let revision: String
    }

    /// The pixel cap a dashboard file card's thumbnail is rendered under.
    ///
    /// The card draws roughly 240 points wide, so 480 is a retina-sharp cover and still
    /// a small image — the same bargain ``ArtboardMap/thumbnailEdge`` makes one size
    /// down. Like the map's, it is a cap on the *shared* PNG endpoint, so a card's
    /// thumbnail is one more entry in this cache rather than a second pipeline, and every
    /// request for it after the first is a hit.
    ///
    /// ``warm(_:)`` deliberately does **not** pre-render it: measured here, one extra
    /// render per file per change occupies this actor long enough to delay a page that is
    /// waiting on it — enough to fail `ViewerBrowserTests.selectionScrollsTheOutlineToItsRow`
    /// reproducibly. Cards are lazy `<img>`s of an already-prepared document, so the cold
    /// path is the cheap half of the pipeline; paying it on demand beats making every
    /// file change slower for a page that is usually not open.
    public static let dashboardThumbnailEdge = 480

    /// The most a render is ever scaled up.
    public let maximumScale: Double

    /// The pixel cap applied when a request names none.
    public let defaultLongestSide: Int

    /// Where a document's fonts are resolved from before it is measured and drawn — and
    /// the resolver every other read the viewer makes of a file settles through, so the
    /// outline and the render measure text in the same faces.
    let fonts: GoogleFontResolver

    /// Where remote image fills are resolved from before a render reads them.
    private let images: RemoteImageResolver

    /// Prepared documents, by file id and canonical theme.
    private var preparations: [String: PreparedDocument] = [:]

    /// Rendered images, by ``Key``.
    private var renderings: [Key: Rendering] = [:]

    /// Generated code, by file id. Not keyed by theme: code generation emits the theme
    /// as CSS custom properties rather than resolving it, so there is one answer per
    /// file however the page is themed.
    private var emissions: [String: ArtboardEmission] = [:]

    /// The prepared form of a file for one theme, preparing it if it is not warm.
    ///
    /// - Parameters:
    ///   - file: The file to prepare.
    ///   - theme: The theme axes to pin, over the document's defaults.
    /// - Returns: The prepared document.
    /// - Throws: ``PenFileError`` if the file cannot be opened, locked or parsed.
    public func prepared(_ file: ViewerFile, theme: [String: String] = [:]) async throws -> PreparedDocument {
        let key = "\(file.id)|\(ThemeQuery.canonical(theme))"
        if let warm = preparations[key] { return warm }
        let prepared = try await Self.prepare(
            file: file, theme: theme, fonts: fonts, images: images
        )
        preparations[key] = prepared
        return prepared
    }

    /// Renders one artboard, or returns the image already rendered for these terms.
    ///
    /// - Parameters:
    ///   - artboardID: The artboard's node id.
    ///   - file: The file it belongs to.
    ///   - theme: The theme axes to pin.
    ///   - longestSide: A cap on the longer side in pixels. `nil` uses
    ///     ``defaultLongestSide``.
    /// - Returns: The PNG and the scale it was rendered at.
    /// - Throws: ``ViewerError/unknownArtboard(id:file:available:)`` when the file has
    ///   no such top-level frame — listing the ones it has — ``ViewerError/noArtboards(file:)``
    ///   when it has none at all, or ``ViewerError/renderFailed(artboard:file:)`` when
    ///   the renderer produces nothing.
    public func png(
        artboard artboardID: String,
        of file: ViewerFile,
        theme: [String: String] = [:],
        longestSide: Int? = nil
    ) async throws -> Rendering {
        let cap = longestSide ?? defaultLongestSide
        let key = Key(
            file: file.id,
            artboard: artboardID,
            theme: ThemeQuery.canonical(theme),
            longestSide: cap
        )
        if let warm = renderings[key] { return warm }

        let prepared = try await prepared(file, theme: theme)
        let artboard = try prepared.artboard(id: artboardID, of: file)

        let rendering = try Self.render(
            artboard: artboard,
            in: prepared,
            file: file,
            scale: scale(for: artboard, cap: cap)
        )
        renderings[key] = rendering
        return rendering
    }

    /// Renders one artboard at an exact scale, bypassing the size cap and the cache.
    ///
    /// ``png(artboard:of:theme:longestSide:)`` exists to keep a page's own image small
    /// and warm, so it clamps to ``maximumScale``. An export is the opposite request —
    /// somebody asked for 3× on purpose — and it is a one-off, so caching it would only
    /// hold a large image nobody asks for twice. Same pipeline, same renderer.
    ///
    /// - Parameters:
    ///   - artboardID: The artboard's node id.
    ///   - file: The file it belongs to.
    ///   - theme: The theme axes to pin.
    ///   - scale: Pixels per layout point.
    /// - Returns: The PNG and the scale it was rendered at.
    /// - Throws: ``ViewerError/unknownArtboard(id:file:available:)``,
    ///   ``ViewerError/noArtboards(file:)`` or ``ViewerError/renderFailed(artboard:file:)``.
    public func image(
        artboard artboardID: String,
        of file: ViewerFile,
        theme: [String: String] = [:],
        scale: Double
    ) async throws -> Rendering {
        let prepared = try await prepared(file, theme: theme)
        let artboard = try prepared.artboard(id: artboardID, of: file)
        return try Self.render(
            artboard: artboard, in: prepared, file: file, scale: max(0.01, scale)
        )
    }

    /// Draws one artboard as a single-page PDF, at its own size in points.
    ///
    /// - Parameters:
    ///   - artboardID: The artboard's node id.
    ///   - file: The file it belongs to.
    ///   - theme: The theme axes to pin.
    /// - Returns: The document's bytes.
    /// - Throws: ``ViewerError/unknownArtboard(id:file:available:)``,
    ///   ``ViewerError/noArtboards(file:)``, or whatever ``Woodcase/PDFExporter`` throws.
    public func pdf(
        artboard artboardID: String,
        of file: ViewerFile,
        theme: [String: String] = [:]
    ) async throws -> Data {
        let prepared = try await prepared(file, theme: theme)
        let artboard = try prepared.artboard(id: artboardID, of: file)
        guard let page = PDFExporter.Page(
            frame: artboard.id, of: prepared.document, layoutRects: prepared.rects,
            imageProvider: PenRenderer.imageProvider(relativeTo: prepared.directory)
        ) else {
            throw ViewerError.unknownArtboard(
                id: artboardID, file: file.id, available: prepared.artboards.map(\.id)
            )
        }
        return try PDFExporter.data(pages: [page])
    }

    /// Every file `woodcase generate react` would write for a document.
    ///
    /// - Parameter file: The file to generate from.
    /// - Returns: The analysis and the emitted files, warm after the first ask.
    /// - Throws: ``Woodcase/PenFileError`` if the file cannot be opened or parsed.
    public func emission(_ file: ViewerFile) async throws -> ArtboardEmission {
        if let warm = emissions[file.id] { return warm }
        let emission = try await ArtboardEmission.of(prepared(file).generationSource)
        emissions[file.id] = emission
        return emission
    }

    /// Drops everything cached for a file.
    ///
    /// - Parameter file: The file that changed.
    public func invalidate(_ file: ViewerFile) {
        preparations = preparations.filter { !$0.key.hasPrefix("\(file.id)|") }
        renderings = renderings.filter { $0.key.file != file.id }
        emissions[file.id] = nil
    }

    /// Drops everything cached, for every file.
    public func invalidateAll() {
        preparations.removeAll()
        renderings.removeAll()
        emissions.removeAll()
    }

    /// Renders every artboard of a file at the default theme, so the first request for
    /// one is a cache hit.
    ///
    /// Failures are swallowed on purpose: warming is an optimization, and a file that
    /// cannot be parsed must fail when it is *asked for*, with an error that says so,
    /// not while the server is starting up.
    ///
    /// - Parameter file: The file to warm.
    public func warm(_ file: ViewerFile) async {
        guard let prepared = try? await prepared(file) else { return }
        for artboard in prepared.artboards {
            _ = try? await png(artboard: artboard.id, of: file)
        }
        // The artboard page asks which generated files this artboard has before it can
        // draw the Export tab, so the emitters run once per change either way. Running
        // them here puts that once off the request path.
        _ = try? await emission(file)
    }

    /// Renders every artboard at the bird's-eye map's cap, so opening the map is a wall
    /// of thumbnails rather than a wall of empty boxes.
    ///
    /// Separate from ``warm(_:)``, and called *after* it, on purpose. A map thumbnail is
    /// a second full render of every artboard — on a twenty-artboard file that is twenty
    /// more renders — and the thing a person is actually waiting for is the artboard they
    /// asked for. So the full-size renders land first and these follow; each is its own
    /// hop through this actor, so a request arriving mid-warm is served between two of
    /// them rather than behind all of them.
    ///
    /// It is deliberately *not* run on every file change, for the reason
    /// ``dashboardThumbnailEdge`` gives: a render per artboard per change makes every
    /// write slower for a page that is usually not open. A map opened after a change
    /// fills in on demand, under the placeholder shimmer.
    ///
    /// - Parameters:
    ///   - file: The file to warm.
    ///   - edge: The pixel cap to render under, which is the one ``ArtboardMap`` asks
    ///     the PNG endpoint for.
    public func warmThumbnails(_ file: ViewerFile, edge: Int = ArtboardMap.thumbnailEdge) async {
        guard let prepared = try? await prepared(file) else { return }
        for artboard in prepared.artboards {
            _ = try? await png(artboard: artboard.id, of: file, longestSide: edge)
        }
    }

    /// Whether an image for these terms is already rendered.
    ///
    /// Asked rather than inferred: a caller deciding whether a warming pass is worth
    /// starting, and a test proving one ran, both need the answer, and timing a render
    /// is not an answer.
    ///
    /// - Parameters:
    ///   - artboardID: The artboard's node id.
    ///   - file: The file it belongs to.
    ///   - theme: The theme axes pinned.
    ///   - longestSide: The cap the image was asked for under. `nil` means
    ///     ``defaultLongestSide``, the one an artboard page asks for.
    /// - Returns: `true` if the next request for it is a cache hit.
    public func isRendered(
        artboard artboardID: String,
        of file: ViewerFile,
        theme: [String: String] = [:],
        longestSide: Int? = nil
    ) -> Bool {
        renderings[Key(
            file: file.id,
            artboard: artboardID,
            theme: ThemeQuery.canonical(theme),
            longestSide: longestSide ?? defaultLongestSide
        )] != nil
    }

    // MARK: - The pipeline

    /// Pixels per point for an artboard under a cap.
    private func scale(for artboard: Artboard, cap: Int) -> Double {
        guard artboard.longestSide > 0 else { return 1 }
        return max(0.01, min(maximumScale, Double(cap) / artboard.longestSide))
    }

    /// Runs the pipeline as far as layout. Mirrors `woodcase render`'s order exactly:
    /// expansion before variable resolution, fonts before layout.
    ///
    /// Expansion keeps the reusable definitions, so a component is an artboard — the
    /// same document `woodcase tree` settles and `woodcase shot` renders. A definition
    /// is what a designer edits, so an agent has to be able to see one; stripping them
    /// left a real Pen file (`banking.pen`, `woodcase-app.pen`), whose top-level frames
    /// are all definitions, showing only the ref-placed copies and offering no way to
    /// open the thing those copies are of. `woodcase render`, which writes files for
    /// delivery rather than for reading, still strips them, so its output is a subset
    /// of ``PreparedDocument/artboards`` rather than the same set.
    ///
    /// - Parameters:
    ///   - file: The .pen file to read.
    ///   - theme: The theme axes to pin over the document's defaults.
    ///   - fonts: The resolver the cache was built with — never
    ///     ``GoogleFontResolver/shared`` directly, so a test can render without
    ///     reaching GitHub or writing the user's `$WOODCASE_HOME`.
    ///   - images: The remote-image resolver, on the same terms.
    /// - Returns: The prepared document.
    private static func prepare(
        file: ViewerFile,
        theme: [String: String],
        fonts: GoogleFontResolver,
        images: RemoteImageResolver
    ) async throws -> PreparedDocument {
        let url = file.url
        let outcome = try await PenFileTransaction.read(at: url, fonts: fonts) { document in
            (document.materializeForGeneration(), document.expanded(for: .canvas), document.documentRevision)
        }
        let (source, expanded, revision) = outcome.value

        let resolved = PenVariableResolver.resolve(expanded, theme: theme)
        await fonts.prepareFonts(for: resolved, relativeTo: url)
        await images.prepareImages(for: resolved)
        let rects = PenLayoutEngine.layout(resolved)

        let artboards: [Artboard] = resolved.children.compactMap { node in
            guard case let .frame(data) = node.kind, let rect = rects[node.id] else { return nil }
            return Artboard(
                id: node.id, name: node.common.name,
                x: rect.x, y: rect.y, width: rect.width, height: rect.height,
                isReusable: node.common.reusable == true,
                isInstance: node.id.contains("/"),
                isSlot: data.slot != nil
            )
        }

        return PreparedDocument(
            document: resolved,
            generationSource: source,
            expanded: expanded,
            rects: rects,
            artboards: artboards,
            revision: revision,
            directory: url.deletingLastPathComponent()
        )
    }

    /// Draws one artboard and encodes it.
    private static func render(
        artboard: Artboard,
        in prepared: PreparedDocument,
        file: ViewerFile,
        scale: Double
    ) throws -> Rendering {
        guard let image = PenRenderer.render(
            prepared.document,
            layoutRects: prepared.rects,
            size: CGSize(width: artboard.width, height: artboard.height),
            scale: CGFloat(scale),
            rootNodeID: artboard.id,
            imageProvider: PenRenderer.imageProvider(relativeTo: prepared.directory)
        ) else {
            throw ViewerError.renderFailed(artboard: artboard.id, file: file.id)
        }
        return try Rendering(
            png: PNGEncoder.encode(image),
            scale: scale,
            artboard: artboard,
            revision: prepared.revision
        )
    }
}
