//
//  PreviewFrameBox.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One preview state inside the production surface it declares.
///
/// The box is the whole of what a ``PreviewFrame`` means on a page: an element carrying
/// `data-frame`, which the stylesheet gives that surface's geometry, wrapped around the
/// state's markup verbatim. Both ``PreviewCanvas`` and ``PreviewStatePage`` draw it, so
/// a state stacked with its siblings and the same state alone are the same picture — if
/// each page wrote its own wrapper the two would drift, and the shot a reviewer took
/// would stop being the thing the canvas showed.
///
/// A state with a ``PreviewState/pinnedWidth`` keeps its surface's ground and is held at
/// that width instead of the surface's — the one way a state shows a pane narrower than
/// the reference window leaves it.
///
/// A ``PreviewFrame/page`` state has no box: a document cannot nest a document. Callers
/// handle that case before they get here — the canvas links to it, and the single-state
/// route serves it whole.
public struct PreviewFrameBox: HTML {
    /// Creates a box.
    ///
    /// - Parameter state: The state to frame. Its ``PreviewState/frame`` decides the
    ///   geometry and its markup is emitted verbatim.
    public init(state: PreviewState) {
        self.state = state
    }

    /// The state being framed.
    public let state: PreviewState

    public var body: some HTML {
        div(.class("v-preview-frame"), .data("frame", value: state.frame.rawValue)) {
            state.html
        }
        // A pinned width is the state's own fact, not a surface's, so it rides on the
        // element rather than in a stylesheet rule keyed by one state's slug.
        .attributes(.style("width: \(state.pinnedWidth ?? 0)px"), when: state.pinnedWidth != nil)
    }
}
