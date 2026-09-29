//
//  ArtboardSteps.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `‹ 2 of 5 ›` — where in the file this artboard is, and the way to the ones either
/// side of it.
///
/// With the map moved out of the canvas, the artboard view has no strip to step along, so
/// stepping lives here: in the footer, beside what is selected, in the one line that was
/// already about *this artboard*. The arrows are real links carrying the whole view
/// state, which is what makes them work with the script off — and what lets the keyboard
/// implement ← and → by clicking them rather than by re-deriving the order. With the
/// script on, ``ViewerScript`` intercepts that click and swaps the artboard in place, so
/// the arrow that steps is not the arrow that reloads.
///
/// Each arrow carries `data-artboard`, so an unread artboard next door shows its dot on
/// the way to it and a step counts as manual navigation for follow, exactly as clicking a
/// box on the map does.
///
/// A file with one artboard renders nothing at all: there is nowhere to step.
public struct ArtboardSteps: HTML {
    /// Creates the control.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboards: Every artboard of the file, in document order.
    ///   - current: The artboard on screen.
    ///   - state: The current view state, which each link carries forward — minus the
    ///     selection, which belongs to the artboard being left.
    public init(file: String, artboards: [Artboard], current: String, state: ViewState) {
        self.file = file
        self.artboards = artboards
        self.current = current
        self.state = state
    }

    /// The file's id.
    public let file: String

    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]

    /// The artboard on screen.
    public let current: String

    /// The current view state.
    public let state: ViewState

    /// Which way a step goes.
    ///
    /// A typed pair rather than a signed number, because the two differ in three ways at
    /// once — the glyph, the word in the hover, and which neighbor they mean — and a
    /// `-1` at the call site says none of them.
    public enum Direction: String, Friendly, CaseIterable {
        /// The artboard before this one in document order.
        case previous
        /// The artboard after it.
        case next

        /// The arrow this direction is drawn as.
        var glyph: String {
            switch self {
            case .previous: "‹"
            case .next: "›"
            }
        }

        /// The class the script clicks to take this step.
        var stepClass: String {
            "v-step-\(rawValue)"
        }

        /// How far along the list it moves.
        var offset: Int {
            switch self {
            case .previous: -1
            case .next: 1
            }
        }
    }

    /// Where the artboard on screen sits in the list, counting from zero.
    public var index: Int? {
        artboards.firstIndex { $0.id == current }
    }

    /// Whether there is anywhere to step.
    public var hasSteps: Bool {
        artboards.count > 1 && index != nil
    }

    /// The artboard one step away, when there is one.
    ///
    /// - Parameter direction: Which way to look.
    /// - Returns: The neighbor, or `nil` at either end — the ends clamp rather than
    ///   wrapping, so ten `›` presses never quietly return you to where you started.
    public func neighbor(_ direction: Direction) -> Artboard? {
        guard let index else { return nil }
        let wanted = index + direction.offset
        guard wanted >= 0, wanted < artboards.count else { return nil }
        return artboards[wanted]
    }

    public var body: some HTML {
        if hasSteps, let index {
            nav(.class("v-steps"), .id("v-artboard-steps")) {
                Step(file: file, direction: .previous, to: neighbor(.previous), state: state)
                span(.class("v-mono v-step-count")) { "\(index + 1) of \(artboards.count)" }
                Step(file: file, direction: .next, to: neighbor(.next), state: state)
            }
        }
    }

    /// One arrow: a link when there is somewhere to go, a dimmed glyph when there is not.
    ///
    /// The end of the list keeps its glyph rather than dropping it, so the counter
    /// between the two arrows does not shift sideways as you step through the file.
    struct Step: HTML {
        /// The file's id.
        let file: String

        /// Which way this arrow goes.
        let direction: Direction

        /// The artboard it leads to, or `nil` at the end of the list.
        let to: Artboard?

        /// The view state to carry.
        let state: ViewState

        var body: some HTML {
            if let to {
                a(
                    .class("v-step \(direction.stepClass)"),
                    .data("artboard", value: to.id),
                    .title("\(direction.rawValue.capitalized) artboard: \(to.name ?? to.id)"),
                    .href(ViewerLink.artboard(
                        file: file, artboard: to.id, state: state.selecting(nil)
                    ))
                ) { direction.glyph }
            } else {
                span(.class("v-step is-end"), .title("No \(direction.rawValue) artboard")) {
                    direction.glyph
                }
            }
        }
    }
}
