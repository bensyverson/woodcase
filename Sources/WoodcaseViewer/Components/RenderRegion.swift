//
//  RenderRegion.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// Everything that moves when the file changes or the selection does: the render, the
/// boxes over it, and the footer naming what is selected.
///
/// One component so it is one swap. The script replaces this whole element on a `change`
/// event and on a selection, which is why the edit markers and the selection footer are
/// *server*-rendered with the right colors and the right rects — there is no hash, no
/// rect math and no footer template written a second time in JavaScript.
public struct RenderRegion: HTML {
    /// Creates a region.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard being shown.
    ///   - artboards: Every artboard of the file, for the footer's prev/next steps.
    ///   - layout: Where every node inside it sits.
    ///   - layoutJSON: That layout, already encoded.
    ///   - state: The current view state.
    ///   - markers: Recent edits to draw.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: String,
        artboard: Artboard,
        artboards: [Artboard] = [],
        layout: ArtboardLayout,
        layoutJSON: String,
        state: ViewState,
        markers: [EditMarker],
        clock: ViewerClock
    ) {
        self.file = file
        self.artboard = artboard
        self.artboards = artboards
        self.layout = layout
        self.layoutJSON = layoutJSON
        self.state = state
        self.markers = markers
        self.clock = clock
    }

    /// The file's id.
    public let file: String
    /// The artboard being shown.
    public let artboard: Artboard
    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]
    /// Where every node inside it sits.
    public let layout: ArtboardLayout
    /// That layout, already encoded.
    public let layoutJSON: String
    /// The current view state.
    public let state: ViewState
    /// Recent edits to draw.
    public let markers: [EditMarker]
    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The selected node's box, when one is selected and this artboard contains it.
    var selection: ArtboardLayout.Node? {
        guard let node = state.node else { return nil }
        return layout.nodes.first { $0.id == node || $0.path == node }
    }

    public var body: some HTML {
        div(.class("v-render-region"), .id(ViewerLink.Fragment.render.target)) {
            div(.class("v-render-scroll")) {
                ArtboardOverlay(
                    file: file,
                    artboard: artboard,
                    layout: layout,
                    layoutJSON: layoutJSON,
                    state: state,
                    markers: markers,
                    clock: clock
                )
            }
            SelectionBar(
                file: file,
                artboard: artboard,
                artboards: artboards,
                scale: layout.scale,
                revision: layout.revision,
                selection: selection,
                state: state
            )
        }
    }
}
