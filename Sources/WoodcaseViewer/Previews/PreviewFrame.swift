//
//  PreviewFrame.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Where a preview state is shown, named as a production surface rather than as a width.
///
/// A component alone on a blank page is the wrong picture: an outline panel is a fixed
/// column in production and a right pane sits against the window's edge. So a state names
/// the surface it lives on, and the page that serves the catalog gives it that surface's
/// geometry — what a reviewer looks at is then the shape the component really renders
/// into.
///
/// The measurements themselves belong to `ViewerStylesheet`, not to this enum. This is
/// the vocabulary; the served host applies it.
public enum PreviewFrame: String, Friendly, CaseIterable {
    /// An atom on one line, at its natural size: an avatar, a live badge, an id chip, a
    /// kind mark.
    case strip

    /// The outline column down the left of a file's page.
    case leftPane = "left-pane"

    /// The activity, details, export and code column down the right.
    case rightPane = "right-pane"

    /// The render column between the two panes, where an artboard or the map is drawn.
    case canvas

    /// The dashboard's centered body column, where the file cards sit.
    ///
    /// Its own surface rather than ``canvas``: the two are both "the middle", but the
    /// canvas is a pane sized by the window between two fixed columns and painted on
    /// the page ground, while this is a padded single column that is the whole width of
    /// the page. A file card shown at the canvas's width is shown at a width the
    /// dashboard never gives it.
    case body

    /// The full-width chrome strip across the top of every page.
    case topBar = "top-bar"

    /// A whole page, served in its own ``ViewerDocument`` rather than framed inside one.
    case page
}
