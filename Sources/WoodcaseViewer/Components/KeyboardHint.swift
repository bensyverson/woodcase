//
//  KeyboardHint.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The "?" badge in the top bar, and the panel of shortcuts it opens.
///
/// The key table itself lives in ``ViewerScript``'s keyboard block, which is what
/// actually dispatches these keys; this component restates it in prose so the shortcuts
/// are discoverable without opening developer tools.
///
/// It was a `title` tooltip, which reads as a badge that does nothing: a tooltip needs a
/// hover held for a second, never appears for a touch or a keyboard, and cannot be
/// selected or read aloud. It is a real popover now — the platform's own, opened by
/// `popovertarget`, so it needs no script and closes on Escape and on a click outside
/// exactly as every other popover on the machine does.
public struct KeyboardHint: HTML {
    /// Creates the hint.
    public init() {}

    /// The popover's id, which the badge points at.
    public static let popoverID = "v-keys"

    /// One line of the panel: what you press, and what happens.
    public struct Shortcut: Friendly {
        /// Creates a shortcut.
        ///
        /// - Parameters:
        ///   - keys: What you press, written the way a keyboard reads.
        ///   - does: What it does, and where it applies.
        public init(keys: String, does: String) {
            self.keys = keys
            self.does = does
        }

        /// What you press.
        public let keys: String

        /// What it does.
        public let does: String
    }

    /// Every shortcut, in the order the key table dispatches them.
    public static let shortcuts: [Shortcut] = [
        Shortcut(keys: "← / →", does: "previous / next artboard, with nothing selected"),
        Shortcut(keys: "↑ / ↓", does: "previous / next outline row, with a node selected"),
        Shortcut(keys: "← / →", does: "collapse / expand the selected row's children"),
        Shortcut(keys: "Enter", does: "on the map, open the artboard the ring is on"),
        Shortcut(keys: "f", does: "presentation mode: the artboard, and nothing else"),
        Shortcut(keys: "Esc", does: "leave presentation, else select the parent node, else go up to the map"),
    ]

    public var body: some HTML {
        button(
            .class("v-key-hint"),
            .type(.button),
            .custom(name: "popovertarget", value: Self.popoverID),
            .custom(name: "aria-label", value: "Keyboard shortcuts")
        ) { "?" }
        div(
            .class("v-key-hint-popover"),
            .id(Self.popoverID),
            .custom(name: "popover")
        ) {
            h2(.class("v-panel-title")) { "Keyboard shortcuts" }
            dl(.class("v-key-list")) {
                for shortcut in Self.shortcuts {
                    dt(.class("v-mono v-key-keys")) { shortcut.keys }
                    dd(.class("v-key-does")) { shortcut.does }
                }
            }
        }
    }
}
