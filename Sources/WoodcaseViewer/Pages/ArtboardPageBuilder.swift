//
//  ArtboardPageBuilder.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Gathers the props for the artboard page and for each of its fragments.
///
/// The page and its fragments are the *same components* with the same props; the only
/// difference is how much of the composition is rendered. That is what makes a live
/// update a server render swapped into place rather than a second implementation of the
/// outline in JavaScript.
public enum ArtboardPageBuilder {
    /// The whole page — the map, or one artboard.
    ///
    /// `/files/{file}` lands on the bird's-eye map, because the first question about a
    /// file you have not seen is what is in it. Two cases skip the map: a file with a
    /// single artboard, where a map of one box is a page you would only click through,
    /// and a `?node=` that names a node, because a link to a node is a link to wherever
    /// that node is. `/files/{file}/artboards/{artboard}` is always the artboard.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The page's HTML.
    /// - Throws: ``ViewerError`` naming the file, artboard or query parameter that could
    ///   not be read.
    public static func page(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let clock = ViewerClock()
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)

        let events = PageData.events(request.context, file: file.url)
        let requested = request.parameters["artboard"]

        // A file with no top-level frames yet — every `woodcase new` starts here. There
        // is nothing to showcase and nothing to map, so the page says so and waits;
        // asking the render endpoint for the artboard that does not exist is how this
        // used to answer a raw JSON 404 on a perfectly healthy file.
        guard !prepared.artboards.isEmpty || requested != nil else {
            return await FileEmptyPage(
                file: file,
                variables: ViewerVariable.rows(of: prepared.document, theme: state.theme, events: events),
                axes: prepared.document.themes ?? [:],
                presence: PageData.presence(request.context),
                state: state,
                clock: clock
            ).render()
        }

        guard let named = requested ?? landing(in: prepared, state: state) else {
            return await MapPage(
                file: file,
                artboards: prepared.artboards,
                revision: prepared.revision,
                variables: ViewerVariable.rows(of: prepared.document, theme: state.theme, events: events),
                axes: prepared.document.themes ?? [:],
                events: events,
                presence: PageData.presence(request.context),
                editors: artboardEditors(in: prepared, events: events, clock: clock),
                state: state,
                clock: clock
            ).render()
        }
        let artboard = try artboard(named: named, in: prepared, file: file)
        let rendering = try await request.context.renders.png(
            artboard: artboard.id, of: file, theme: state.theme
        )
        guard let layout = ArtboardLayout.of(artboard: artboard, in: prepared, scale: rendering.scale) else {
            throw ViewerError.renderFailed(artboard: artboard.id, file: file.id)
        }

        let markers = EditMarker.markers(in: events, clock: clock)
        let outline = try await rows(
            of: file, artboard: artboard.id, state: state, fonts: request.context.renders.fonts
        )
        let emission = try await request.context.renders.emission(file)
        let selection = try await selection(
            of: file, state: state, prepared: prepared, fonts: request.context.renders.fonts
        )

        return await ArtboardPage(
            file: file,
            artboard: artboard,
            artboards: prepared.artboards,
            layout: layout,
            layoutJSON: json(layout),
            rows: outline,
            variables: ViewerVariable.rows(of: prepared.document, theme: state.theme, events: events),
            axes: prepared.document.themes ?? [:],
            events: events,
            presence: PageData.presence(request.context),
            markers: markers,
            editors: editors(from: markers),
            details: selection.details,
            unresolved: selection.unresolved,
            targets: targets(for: artboard.id, in: emission),
            // Rendered whether or not the Code tab is the one showing, like every other
            // panel of the right pane: the emission is already warm for `targets`, so the
            // pane costs a lookup and switching to it costs no round trip.
            code: ArtboardCode.of(artboard: artboard.id, in: emission, target: state.lang ?? .react),
            state: state,
            clock: clock
        ).render()
    }

    // MARK: - Pieces

    /// Which artboard `GET /files/{file}` should open, or `nil` for the map.
    ///
    /// Two things beat the map. A file with a single artboard goes straight to it: a map
    /// of one box is a page you would only ever click through. And a `?node=` that names
    /// a node opens the artboard that holds it, because a link to a node is a link to
    /// wherever that node is — `/files/{file}?node=Vr7Kd` is a URL an agent pastes, and
    /// landing it on a map that cannot show the selection would be a worse answer than
    /// the one it used to get.
    ///
    /// A file with *no* artboards never reaches this: ``page(_:)`` answers it with
    /// ``FileEmptyPage`` before asking which one to open. It used to answer `""` here,
    /// which is how a healthy new file 404'd with an error quoting an empty id.
    ///
    /// - Parameters:
    ///   - prepared: The prepared document.
    ///   - state: The view state, whose `?node=` decides the second case.
    /// - Returns: The artboard id to open, or `nil` to draw the map.
    static func landing(in prepared: PreparedDocument, state: ViewState) -> String? {
        guard prepared.artboards.count > 1 else {
            return prepared.artboards.first?.id
        }
        guard let node = state.node, !node.isEmpty else { return nil }
        return prepared.artboardIDs(containing: [node]).first
    }

    /// Which identities touched something inside which artboard, keyed by artboard id.
    ///
    /// The node-level markers the render draws are too fine for a thumbnail 24 pixels
    /// across, so the map marks the *artboard* instead: same log, same recency window,
    /// same color, one level up. It is the map's answer to "where is the work
    /// happening".
    ///
    /// - Parameters:
    ///   - prepared: The prepared document, which maps node ids to artboards.
    ///   - events: The file's recent activity.
    ///   - clock: The moment the page is rendered for.
    /// - Returns: The identities per artboard, in the log's order of first appearance.
    static func artboardEditors(
        in prepared: PreparedDocument,
        events: [ActivityEvent],
        clock: ViewerClock
    ) -> [String: [String]] {
        var editors: [String: [String]] = [:]
        for marker in EditMarker.markers(in: events, clock: clock) {
            for artboard in prepared.artboardIDs(containing: [marker.node]) {
                var identities = editors[artboard] ?? []
                for identity in marker.identities where !identities.contains(identity) {
                    identities.append(identity)
                }
                editors[artboard] = identities
            }
        }
        return editors
    }

    /// The artboard a request names, or the file's first.
    ///
    /// - Parameters:
    ///   - id: The `{artboard}` parameter, or `nil` on `/files/{file}`.
    ///   - prepared: The prepared document.
    ///   - file: The file, for the error.
    /// - Returns: The artboard to show.
    /// - Throws: ``ViewerError/unknownArtboard(id:file:available:)`` listing the ids that
    ///   do exist, or ``ViewerError/noArtboards(file:)`` when there are none — two
    ///   different answers, so that no message ever quotes an id nobody named.
    static func artboard(
        named id: String?,
        in prepared: PreparedDocument,
        file: ViewerFile
    ) throws -> Artboard {
        guard let id else {
            guard let first = prepared.artboards.first else {
                throw ViewerError.noArtboards(file: file.id)
            }
            return first
        }
        return try prepared.artboard(id: id, of: file)
    }

    /// The settled tree rows for the outline: the showcased artboard's tree, and nothing
    /// beside it.
    ///
    /// The tree verb's rows, read through the same call the `tree.json` endpoint makes,
    /// so the panel and the JSON cannot disagree — except for `root`, which `tree.json`
    /// leaves to the caller and this always pins to the artboard on screen. A file
    /// carries every artboard, every component definition and every instance in one flat
    /// store; an outline that walked the whole thing would print all of them at once
    /// however few belong to the one you are looking at.
    ///
    /// Instances are always walked into, which the verb makes a flag (`--expand`) and the
    /// viewer does not. The render is drawn from the *expanded* document — every node
    /// inside an instance is on screen and can be clicked — and an outline that stopped
    /// at the `ref` would have no row to select for what a person just clicked. The
    /// outline describes what is on the render; that is not a preference.
    ///
    /// `root` is ``ArtboardLayout/address(of:under:)`` applied to `artboard`, not the
    /// artboard's id as-is: a ref-placed artboard's id is the expansion's own compound
    /// id (`<ref>/<component root>`), which names no node the resolver accepts — the
    /// component root is not a step of its own address, the same gap
    /// ``ArtboardLayout`` closes for a click on the render. A plain top-level frame's id
    /// carries no such prefix, so the translation is a no-op for it.
    ///
    /// - Parameters:
    ///   - file: The file to read.
    ///   - artboard: The artboard on screen — ``Artboard/id``, which may be a plain
    ///     top-level frame's or a ref-placed instance's compound id.
    ///   - state: The view state, whose theme and depth mirror the verb's flags.
    ///   - fonts: The resolver the rows settle through — the render cache's, so the
    ///     outline measures text in the faces the render draws.
    /// - Returns: The rows.
    /// - Throws: ``ViewerError/unknownNode(address:file:reason:)`` when the artboard's
    ///   own address resolves to nothing in the live document — never an empty listing.
    static func rows(
        of file: ViewerFile, artboard: String, state: ViewState, fonts: GoogleFontResolver?
    ) async throws -> [TreeRow] {
        let root = ArtboardLayout.address(of: artboard, under: nil)
        do {
            return try await PenFileTransaction.read(at: file.url, fonts: fonts) { document in
                try TreeView.rows(
                    of: document,
                    root: root,
                    depth: state.depth,
                    expandInstances: true,
                    theme: state.theme.isEmpty ? nil : state.theme,
                    properties: []
                )
            }.value
        } catch let error as EditingError {
            throw ViewerError.unknownNode(address: root, file: file.id, reason: String(describing: error))
        }
    }

    /// What the Details pane shows: the selected node, or the address that named nothing.
    ///
    /// A `?node=` that resolves to no node does *not* fail the page. A link an agent
    /// pasted after a rename should still open the artboard; the pane says the address
    /// went nowhere, which is the part a reader needs, and the rest of the page is
    /// exactly as useful as it was.
    ///
    /// - Parameters:
    ///   - file: The file to read.
    ///   - state: The view state, whose `node` is the address and whose theme decides
    ///     what a variable is worth.
    ///   - prepared: The warm expansion, which carries both the authored and the
    ///     resolved trees.
    ///   - fonts: The resolver the document is read with — the render cache's.
    /// - Returns: The details, or the address that named nothing, or neither.
    /// - Throws: ``Woodcase/PenFileError`` if the file cannot be opened or locked.
    static func selection(
        of file: ViewerFile,
        state: ViewState,
        prepared: PreparedDocument,
        fonts: GoogleFontResolver?
    ) async throws -> (details: NodeDetails?, unresolved: String?) {
        guard let node = state.node, !node.isEmpty else { return (nil, nil) }
        let details = try await PenFileTransaction.read(at: file.url, fonts: fonts) { document in
            try? NodeDetails.of(
                address: node,
                in: document,
                expanded: prepared.expanded,
                resolved: prepared.document
            )
        }.value
        return (details, details == nil ? node : nil)
    }

    /// The generated files this document actually writes for one artboard.
    ///
    /// Asked of the emitter rather than assumed: a placed instance has no `.tsx` of its
    /// own, and `states.css` exists only when some component declares a state. Offering
    /// a file that would 404 is the thing the export form exists not to do.
    ///
    /// - Parameters:
    ///   - artboard: The artboard's node id.
    ///   - emission: The whole generated set.
    /// - Returns: The targets that produce a file, in ``ViewerCodeTarget``'s own order.
    static func targets(for artboard: String, in emission: ArtboardEmission) -> [ViewerCodeTarget] {
        ViewerCodeTarget.allCases.filter {
            ArtboardCode.of(artboard: artboard, in: emission, target: $0) != nil
        }
    }

    /// Which identities touched which node, keyed by node id.
    ///
    /// - Parameter markers: The recent edits.
    /// - Returns: The identities per node, in the log's order of first appearance.
    static func editors(from markers: [EditMarker]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: markers.map { ($0.node, $0.identities) })
    }

    /// A layout as inline JSON.
    ///
    /// - Parameter layout: The layout to encode.
    /// - Returns: The JSON, or an empty object if it cannot be encoded — the overlay
    ///   then draws nothing, which is a worse page but never a broken one.
    ///
    /// `<` is written as its JSON escape, because this lands inside a `<script>` element
    /// and a node named `</script>` would otherwise end it.
    static func json(_ layout: ArtboardLayout) -> String {
        guard let data = try? ViewerJSON.encoder.encode(layout) else { return "{}" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003C")
    }
}
