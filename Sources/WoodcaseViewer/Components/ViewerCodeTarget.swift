//
//  ViewerCodeTarget.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One file `woodcase generate react` writes, offered on its own for one artboard.
///
/// These are the emitters' *actual* outputs, not a menu of languages the viewer wishes
/// it had: `generate` has exactly one target, and its emitters produce a `.tsx` per
/// component and page (``ReactEmitter``), a `theme.css` (``ThemeEmitter``), a
/// `states.css` when any component has interactive states (``StateEmitter``), and a
/// `manifest.json` (``ManifestEmitter``). Anything else would be a promise the CLI does
/// not keep.
///
/// A whole-package download is deliberately not here — `generate react --output` already
/// writes the directory, and the parked item says so.
public enum ViewerCodeTarget: String, Friendly, CaseIterable {
    /// The artboard's own React component or page file.
    case react
    /// The theme's CSS custom properties, one selector per axis combination.
    case themeCSS = "theme-css"
    /// The interactive states' CSS, when any component declares one.
    case statesCSS = "states-css"
    /// The manifest of components, pages, axes and variables.
    case manifest

    /// The word in the picker.
    public var label: String {
        switch self {
        case .react: "React (.tsx)"
        case .themeCSS: "Theme (.css)"
        case .statesCSS: "States (.css)"
        case .manifest: "Manifest (.json)"
        }
    }

    /// The content type the download is sent with.
    ///
    /// A generated `.tsx` has no registered type, and `text/plain` is the honest answer
    /// for one — a browser shows it rather than guessing at an application.
    public var mediaType: String {
        switch self {
        case .react, .themeCSS, .statesCSS: "text/plain; charset=utf-8"
        case .manifest: "application/json; charset=utf-8"
        }
    }

    /// The `<pre>` language hint, for anything that wants to color the pane later.
    public var syntax: String {
        switch self {
        case .react: "tsx"
        case .themeCSS, .statesCSS: "css"
        case .manifest: "json"
        }
    }
}
