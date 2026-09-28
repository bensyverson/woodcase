//
//  ViewerTab.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Which of the right pane's four panels is on screen.
///
/// The pane is tabbed rather than stacked because its jobs answer different questions —
/// *what has been happening*, *what is this node*, *give me this artboard as a file*,
/// *what does it generate* — and only one of them is ever the reason you looked over
/// there.
///
/// It is view state, so it lives in the query (`?tab=details`) and a pasted URL reopens
/// the tab it was written from. Every panel is server-rendered on every page; the tab
/// only decides which one the stylesheet shows, so switching works with the script off
/// and a fragment swap never has to care which tab is current.
public enum ViewerTab: String, Friendly, CaseIterable {
    /// The activity feed — what has been written to this file.
    case activity
    /// The selected node's attributes, and where each of them came from.
    case details
    /// This artboard as a file: an image, a document, or generated code.
    case export
    /// The generated file itself — what `woodcase generate` writes for this artboard.
    ///
    /// It used to be the other half of a split canvas, opened by a switch at the end of
    /// this bar. The split cost the render a third of its width for a panel most
    /// readings of a page never open, and the code is one more answer *about* the
    /// artboard on screen — the same shape as Details and Export. So it is a tab.
    case code

    /// The tab a page opens on when the query names none.
    ///
    /// Activity, because a viewer with nothing selected is watching rather than
    /// inspecting. Selecting a node moves to ``details`` — see
    /// ``ViewState/selecting(_:)``.
    public static let fallback = ViewerTab.activity

    /// The word on the tab.
    public var label: String {
        switch self {
        case .activity: "Activity"
        case .details: "Details"
        case .export: "Export"
        case .code: "Code"
        }
    }
}
