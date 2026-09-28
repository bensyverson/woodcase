//
//  ArtboardPageBuilder+Fragments.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The props for each of the page's fragments.
///
/// A fragment is the *same component* the whole page rendered, with the same props, served
/// on its own — which is what makes a live update a server render swapped into place
/// rather than a second implementation in JavaScript. They live beside the page rather
/// than inside it because there are ten of them and one page.
public extension ArtboardPageBuilder {
    /// The details fragment — `GET /files/{file}/details`.
    ///
    /// Whole-file rather than per-artboard: which node it describes rides in `?node=`,
    /// and a node inside one artboard is described the same way from any of them.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The panel's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func details(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let selection = try await selection(
            of: file, state: state, prepared: prepared, fonts: request.context.renders.fonts
        )
        return DetailsPanel(
            details: selection.details, file: file.id, unresolved: selection.unresolved
        ).render()
    }

    /// The code fragment — `GET /files/{file}/artboards/{artboard}/code`.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The pane's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func code(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let artboard = try artboard(named: request.parameters["artboard"], in: prepared, file: file)
        let emission = try await request.context.renders.emission(file)
        return CodePane(
            file: file.id,
            artboard: artboard.id,
            code: ArtboardCode.of(
                artboard: artboard.id, in: emission, target: state.lang ?? .react
            ),
            targets: targets(for: artboard.id, in: emission),
            state: state
        ).render()
    }

    /// The render fragment — `GET /files/{file}/artboards/{artboard}/render`.
    ///
    /// Everything that moves: the image, the edit markers, the selection box and the
    /// footer. It is a fragment rather than JavaScript because the markers need an
    /// identity's hashed colour and the boxes need absolute rects, and re-deriving either
    /// on the client would be a second implementation of a component.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The region's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func render(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let clock = ViewerClock()
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let artboard = try artboard(named: request.parameters["artboard"], in: prepared, file: file)
        let rendering = try await request.context.renders.png(
            artboard: artboard.id, of: file, theme: state.theme
        )
        guard let layout = ArtboardLayout.of(artboard: artboard, in: prepared, scale: rendering.scale) else {
            throw ViewerError.renderFailed(artboard: artboard.id, file: file.id)
        }
        let events = PageData.events(request.context, file: file.url)
        return RenderRegion(
            file: file.id,
            artboard: artboard,
            artboards: prepared.artboards,
            layout: layout,
            layoutJSON: json(layout),
            state: state,
            markers: EditMarker.markers(in: events, clock: clock),
            clock: clock
        ).render()
    }

    /// The bird's-eye map — `GET /files/{file}/map`.
    ///
    /// Its own fragment because the list of artboards changes when the file does: an
    /// agent adding a top-level frame is a new box on a page nobody reloaded, and it
    /// arrives at the canvas position the write gave it. Whole-file, because nothing on
    /// the map is current.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The map's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func map(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let clock = ViewerClock()
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let events = PageData.events(request.context, file: file.url)
        return ArtboardMap(
            file: file.id,
            artboards: prepared.artboards,
            state: state,
            editors: artboardEditors(in: prepared, events: events, clock: clock)
        ).render()
    }

    /// The map page's outline — `GET /files/{file}/artboards`.
    ///
    /// One row per artboard rather than one per node. It answers with the outline's own
    /// element id, so it swaps into the same slot the node outline occupies on the
    /// artboard page; the two never both exist.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The panel's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func artboards(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let clock = ViewerClock()
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let events = PageData.events(request.context, file: file.url)
        return ArtboardOutline(
            artboards: prepared.artboards,
            revision: prepared.revision,
            file: file.id,
            state: state,
            editors: artboardEditors(in: prepared, events: events, clock: clock)
        ).render()
    }

    /// The Follow control — `GET /files/{file}/artboards/{artboard}/follow`, and
    /// `GET /files/{file}/follow` for the map page.
    ///
    /// Its own fragment because it changes without the file changing: any manual
    /// navigation drops follow to nobody, and the control that says so — and offers to
    /// resume — is rendered here rather than assembled in JavaScript. The artboard in the
    /// path is only the page the form submits back to; the map has none, and follows the
    /// same identities to the same effect — a matching write drills into the artboard it
    /// touched.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The control's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func follow(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        var action: String = ViewerLink.file(file.id)
        if let named = request.parameters["artboard"] {
            let prepared = try await request.context.renders.prepared(file, theme: state.theme)
            let artboard = try artboard(named: named, in: prepared, file: file)
            action = ViewerLink.artboard(file: file.id, artboard: artboard.id)
        }
        return await FollowPicker(
            identities: PageData.presence(request.context),
            state: state,
            action: action
        ).render()
    }

    /// The outline fragment — `GET /files/{file}/artboards/{artboard}/outline`.
    ///
    /// It names an artboard although the tree is the whole file's, because every row's
    /// link has to select the node *into* the artboard on screen.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The panel's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func outline(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let clock = ViewerClock()
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let artboard = try artboard(named: request.parameters["artboard"], in: prepared, file: file)
        let events = PageData.events(request.context, file: file.url)
        let outline = try await rows(
            of: file, artboard: artboard.id, state: state, fonts: request.context.renders.fonts
        )
        return OutlinePanel(
            rows: outline,
            revision: prepared.revision,
            file: file.id,
            artboard: artboard.id,
            state: state,
            editors: editors(from: EditMarker.markers(in: events, clock: clock))
        ).render()
    }

    /// The variables fragment — `GET /files/{file}/variables`.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The panel's HTML.
    /// - Throws: ``ViewerError`` naming what could not be read.
    static func variables(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        let state = try ViewState.of(request)
        let prepared = try await request.context.renders.prepared(file, theme: state.theme)
        let events = PageData.events(request.context, file: file.url)
        return VariablesPanel(
            variables: ViewerVariable.rows(of: prepared.document, theme: state.theme, events: events),
            axes: prepared.document.themes ?? [:],
            clock: ViewerClock()
        ).render()
    }

    /// The activity fragment — `GET /files/{file}/activity`.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The feed's HTML.
    /// - Throws: ``ViewerError/unknownFile(id:)`` when the id names no watched file.
    static func activity(_ request: ViewerRequest) async throws -> String {
        let file = try await request.file()
        return ActivityFeed(
            events: PageData.events(request.context, file: file.url),
            clock: ViewerClock(),
            scope: "this file · all identities",
            limit: 40
        ).render()
    }

    /// The presence fragment — `GET /files/{file}/presence`.
    ///
    /// Presence is global; the path names a file only so every fragment is reached the
    /// same way and the script needs one URL builder rather than two.
    ///
    /// - Parameter request: The request to render for.
    /// - Returns: The stack's HTML.
    static func presence(_ request: ViewerRequest) async -> String {
        await PresenceStack(
            identities: PageData.presence(request.context),
            clock: ViewerClock()
        ).render()
    }
}
