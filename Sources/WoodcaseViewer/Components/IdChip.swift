//
//  IdChip.swift
//  WoodcaseViewer
//

import Elementary
import Foundation

/// A node id, drawn as a small monospace chip that copies itself when clicked.
///
/// Every id on the page is a candidate for pasting into a `woodcase` command, so every
/// one of them is this chip — in the outline, the selection footer, and an activity
/// row's expanded detail. The click is handled by ``ViewerScript``, in a capture-phase
/// listener that stops the click from reaching whatever the chip sits inside (an outline
/// row is itself a link), so copying an id never also selects or navigates.
public struct IdChip: HTML {
    /// Creates a chip.
    ///
    /// - Parameters:
    ///   - id: The id to display and copy.
    ///   - extraClasses: Additional classes the caller's own stylesheet rules key on
    ///     (`"v-outline-id"`), space-separated. Empty by default.
    ///   - copied: Whether to render the chip in the flash it wears for the 1.2 s after
    ///     a successful copy. Always `false` on the server — see ``copied``.
    public init(id: String, extraClasses: String = "", copied: Bool = false) {
        self.id = id
        self.extraClasses = extraClasses
        self.copied = copied
    }

    /// The id to display and copy.
    public let id: String

    /// Additional classes riding alongside the chip's own.
    public let extraClasses: String

    /// Whether the chip is in its just-copied flash.
    ///
    /// The server always renders `false`: the flash belongs to one browser's click and
    /// no page arrives in it. It exists so the state can be *declared* — a preview sets
    /// exactly what ``ViewerScript`` sets on a copy (the `is-copied` class), so what a
    /// reviewer looks at is the markup the page really wears rather than a mock of it.
    public let copied: Bool

    public var body: some HTML {
        // Both words are always here; the class decides which one shows. The id stays in
        // flow and keeps the chip's width, and `copied` is laid over it, so the flash
        // never reflows the row the chip sits in and the script never writes text.
        span(
            .class("v-id-chip"),
            .data("copy-id", value: id),
            .title("Click to copy \(id)")
        ) {
            span(.class("v-id-chip-id")) { id }
            span(.class("v-copied"), .custom(name: "aria-hidden", value: "true")) { "copied" }
        }
        .attributes(.class(extraClasses), when: !extraClasses.isEmpty)
        .attributes(.class("is-copied"), when: copied)
    }
}
