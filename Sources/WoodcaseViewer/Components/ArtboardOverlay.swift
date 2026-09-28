//
//  ArtboardOverlay.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The render, and the boxes drawn over it.
///
/// The boxes are HTML positioned over the PNG — not painted into it. Three reasons, and
/// the third is the one that decided it: an outline that fades or pins would otherwise
/// need a re-render per frame; the image is cached per artboard, theme and size, and
/// baking a selection into it would defeat that cache; and an agent asking for the same
/// URL must get the same bytes whatever anyone has selected.
///
/// The selected node's box and every recent edit marker are rendered **here, on the
/// server**, so the page is correct with the script switched off. The script's job is to
/// move them as events arrive, fade them, and pin one on click.
///
/// ``ArtboardLayout`` rides along as inline JSON so the script can position a box for
/// any node without a second request.
public struct ArtboardOverlay: HTML {
    /// Creates an overlay.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard being shown.
    ///   - layout: Where every node inside it sits.
    ///   - layoutJSON: That layout, already encoded, so the component stays a pure
    ///     function and encoding failures are handled where they can be reported.
    ///   - state: The current view state, whose theme the image URL carries.
    ///   - markers: Recent edits to draw.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: String,
        artboard: Artboard,
        layout: ArtboardLayout,
        layoutJSON: String,
        state: ViewState,
        markers: [EditMarker],
        clock: ViewerClock
    ) {
        self.file = file
        self.artboard = artboard
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

    /// Where every node inside it sits.
    public let layout: ArtboardLayout

    /// The layout, already encoded as JSON.
    public let layoutJSON: String

    /// The current view state.
    public let state: ViewState

    /// Recent edits to draw.
    public let markers: [EditMarker]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The selected node's box, when one is selected and the artboard contains it.
    var selected: ArtboardLayout.Node? {
        guard let node = state.node else { return nil }
        return layout.nodes.first { $0.id == node || $0.path == node }
    }

    /// The image's laid-out width, in CSS pixels — the artboard's *point* width.
    ///
    /// Not its pixel width. The PNG is rendered at ``ArtboardLayout/scale`` device pixels
    /// per point, and giving the element the point size is what makes the browser
    /// downsample a 2× render into a crisp image rather than draw it at twice life size.
    var laidOutWidth: Int {
        Int(artboard.width.rounded())
    }

    /// The image's laid-out height, in CSS pixels.
    var laidOutHeight: Int {
        Int(artboard.height.rounded())
    }

    /// The CSS custom properties that place one box.
    ///
    /// - Parameter node: The node to place.
    /// - Returns: A `style` value in layout points; the stylesheet multiplies by the
    ///   scale, so a re-render at a different size moves every box by changing one
    ///   number.
    static func placement(_ node: ArtboardLayout.Node) -> String {
        "--v-x: \(OutlineRow.number(node.x)); --v-y: \(OutlineRow.number(node.y)); "
            + "--v-w: \(OutlineRow.number(node.width)); --v-h: \(OutlineRow.number(node.height))"
    }

    public var body: some HTML {
        div(
            .class("v-stage"),
            .id("v-stage"),
            .data("file", value: file),
            .data("artboard", value: artboard.id),
            .data("density", value: String(layout.scale)),
            // `--v-scale` is CSS pixels per layout point — how big the artboard is drawn,
            // not how densely it was rendered. It ships as 1 so the page is right at full
            // size with the script off; the script lowers it to fit the pane, and every
            // box follows because every box is placed in points and multiplied by it.
            .style("--v-scale: 1; --v-art-w: \(OutlineRow.number(artboard.width)); --v-art-h: \(OutlineRow.number(artboard.height))")
        ) {
            img(
                .class("v-render"),
                .id("v-render"),
                .src(ViewerLink.png(file: file, artboard: artboard.id, state: state)),
                .alt(artboard.name ?? artboard.id),
                .width(laidOutWidth),
                .height(laidOutHeight)
            )
            div(.class("v-overlay"), .id("v-overlay")) {
                if let selected {
                    div(.class("v-box is-selected"), .data("node", value: selected.id), .style(Self.placement(selected))) {
                        span(.class("v-box-tag")) {
                            // The same front-truncation recipe as the selection footer:
                            // the wrapper lays out right-to-left so the ellipsis eats the
                            // head, and the `<bdi>` keeps the characters in written order.
                            span(.class("v-box-path")) { bdi { selected.path } }
                        }
                    }
                }
                for marker in markers {
                    if let node = layout.node(id: marker.node) {
                        MarkerBox(marker: marker, node: node, clock: clock)
                    }
                }
            }
            script(.type("application/json"), .id("v-layout")) { HTMLRaw(layoutJSON) }
        }
    }

    /// One recent edit's box and tag.
    struct MarkerBox: HTML {
        /// The edit to draw.
        let marker: EditMarker

        /// Where the node it touched sits.
        let node: ArtboardLayout.Node

        /// The moment the page is rendered for.
        let clock: ViewerClock

        var body: some HTML {
            div(
                .class("v-box is-edit"),
                .data("node", value: marker.node),
                .data("editors", value: marker.identities.joined(separator: " ")),
                .style(
                    "\(ArtboardOverlay.placement(node)); --v-actor: \(marker.color.css); "
                        + "--v-actor-ink: \(marker.color.ink.rawValue)"
                )
            ) {
                span(.class("v-box-tag v-edit-tag")) {
                    for identity in marker.identities {
                        AvatarView(identity: identity)
                    }
                    span(.class("v-edit-who")) { marker.identities.joined(separator: ", ") }
                    span(.class("v-edit-op")) { "\(marker.op.rawValue) \(clock.age(marker.time, style: .compact))" }
                }
            }
        }
    }
}
