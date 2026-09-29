//
//  ViewerDocument.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The document every page is wrapped in: the head, the stylesheet, the script, and the
/// body class the stylesheet lays out from.
///
/// Pages are compositions and own no markup of their own; this is the one place a
/// `<head>` is written, which is why adding a page cannot forget the stylesheet.
///
/// Light and dark follow the operating system through `prefers-color-scheme`. There is
/// no theme toggle in the chrome on purpose: the toggle in the top bar is the *file's*
/// theme axes, and two switches that both say "dark" would be a permanent source of
/// confusion.
public struct ViewerDocument<Content: HTML>: HTMLDocument {
    /// Creates a document.
    ///
    /// - Parameters:
    ///   - title: The page's title.
    ///   - layout: Which body layout the stylesheet should use.
    ///   - content: The page's body.
    public init(title: String, layout: Layout, @ContentBuilder content: () -> Content) {
        self.title = title
        self.layout = layout
        self.content = content()
    }

    /// Which body layout the stylesheet should use.
    ///
    /// A named layout rather than a set of classes each page assembles: three pages, three
    /// shapes, and the stylesheet owns what each one means.
    public enum Layout: String, Friendly {
        /// The cross-file dashboard: one centered column.
        case dashboard
        /// One artboard: outline left, render center, activity right.
        case artboard
        /// Nothing to show yet: one centered card.
        case empty
        /// The preview catalog: one centered column of components or of framed states.
        ///
        /// The dashboard's shape rather than a shape of its own, because the catalog is
        /// read the way the dashboard is — top to bottom, one column — and a second
        /// scrolling-column layout would be the same rule written twice.
        case preview
    }

    /// The page's title.
    public let title: String

    /// Which body layout the stylesheet should use.
    public let layout: Layout

    /// The page's body.
    public let content: Content

    public var lang: String {
        "en"
    }

    public var bodyAttributes: [HTMLAttribute<HTMLTag.body>] {
        [.class("v-body v-layout-\(layout.rawValue)")]
    }

    public var head: some HTML {
        meta(.name(.viewport), .content("width=device-width, initial-scale=1"))
        link(.rel(.stylesheet), .href(ViewerLink.stylesheet))
        script(.src(ViewerLink.script), .custom(name: "defer"))
    }

    public var body: some HTML {
        content
    }
}
