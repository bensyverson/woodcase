//
//  FileCard.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One file on the dashboard: a rendered thumbnail of the artboard that stands for it,
/// its name and path, how many artboards it has, and what last happened to it.
///
/// A card rather than a row, because the thumbnail is the answer to "which file is
/// this?" and a row 30 pixels tall cannot carry one. The grid also fits far more of the
/// recent files on a screen than a list of full-width rows did, which is what the
/// dashboard is for.
///
/// The whole card is the link, because the card *is* the file.
///
/// The thumbnail is an ordinary `<img>` pointing at the PNG endpoint
/// (``ViewerLink/png(file:artboard:maxEdge:state:)``) capped at
/// ``RenderCache/dashboardThumbnailEdge`` — the same warm render pipeline the artboard
/// view and the bird's-eye map read, never a second renderer — and it is lazy, so a
/// dashboard listing forty files fetches the handful actually on screen.
///
/// A file that could not be parsed keeps its card and says why, in the space the
/// thumbnail would have filled. A dashboard that silently dropped a broken file would
/// report that everything is fine.
public struct FileCard: HTML {
    /// Creates a card.
    ///
    /// - Parameters:
    ///   - summary: The file, as `GET /files` reports it.
    ///   - clock: The moment the page is rendered for.
    public init(summary: FileListReport.Summary, clock: ViewerClock) {
        self.summary = summary
        self.clock = clock
    }

    /// The file, as `GET /files` reports it.
    public let summary: FileListReport.Summary

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// How many artboards the file has, as text.
    var artboardsText: String {
        let count = summary.artboards.count
        return "\(count) \(count == 1 ? "artboard" : "artboards")"
    }

    public var body: some HTML {
        a(
            .class("v-file-card"),
            .href(ViewerLink.file(summary.id)),
            .data("file", value: summary.id)
        ) {
            span(.class("v-file-thumb")) { thumbnail }
            span(.class("v-file-identity")) {
                span(.class("v-file-name")) { summary.name }
                span(.class("v-mono v-file-path")) { summary.path }
            }
            span(.class("v-row v-file-foot")) {
                span(.class("v-file-count")) { artboardsText }
                span(.class("v-file-change")) { change }
            }
        }
        .attributes(.class("is-broken"), when: summary.error != nil)
    }

    /// The cover render, or what stands in its place.
    @HTMLBuilder
    private var thumbnail: some HTML {
        if let cover = summary.cover {
            img(
                .class("v-file-shot"),
                .src(ViewerLink.png(
                    file: summary.id,
                    artboard: cover.id,
                    maxEdge: RenderCache.dashboardThumbnailEdge
                )),
                // Decorative: the file's name is directly beneath it, and a screen
                // reader repeating it would read every card twice.
                .alt(""),
                .width(Int(cover.width.rounded())),
                .height(Int(cover.height.rounded())),
                .custom(name: "loading", value: "lazy"),
                .custom(name: "decoding", value: "async")
            )
        } else if let error = summary.error {
            span(.class("v-file-error"), .title(error)) { "unreadable" }
        } else {
            span(.class("v-file-blank")) { "no artboards" }
        }
    }

    /// The last recorded edit, or a note that there is none.
    ///
    /// Who and when, and not the verb the row used to spell out: a card's footer is one
    /// narrow line, the identity already rides in the ``AvatarView``'s `title`, and the
    /// activity feed directly below on this same page carries every verb with its nodes.
    @HTMLBuilder
    private var change: some HTML {
        if let change = summary.lastChange {
            span(.class("v-file-when")) { clock.age(change.time, style: .long) }
            AvatarView(identity: change.identity)
        } else {
            span(.class("v-file-when is-quiet")) { "no changes" }
        }
    }
}
