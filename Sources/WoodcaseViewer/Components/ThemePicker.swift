//
//  ThemePicker.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One dropdown per theme axis the *file* declares — a control, not a label.
///
/// The header's theme reading is the file's own axes, settled the way the render is, and
/// changing one re-renders the artboard down the same path `woodcase shot --theme`
/// takes. The site's own light and dark follow the operating system and are nothing to
/// do with this.
///
/// ## Why each axis is its own form
///
/// `?theme=` is one parameter carrying every pin (`Mode:Dark,Base:Slate`). A form with
/// several controls named `theme` would submit several `theme=` parameters, and the
/// server reads one. So each axis is a form of its own whose option values are the
/// *whole* pin set with that axis swapped — one control, one complete answer, and the
/// query the page produces is byte-for-byte the query it documents.
///
/// The submit button is real and is hidden by CSS once the script has marked the
/// document as scripted, so the control is a plain form when it has to be and a
/// change-to-apply dropdown when it can be.
public struct ThemePicker: HTML {
    /// Creates a picker.
    ///
    /// - Parameters:
    ///   - axes: The document's theme axes and their values.
    ///   - state: The current view state, whose other parts ride along as hidden fields.
    ///   - action: The path the form submits to — the page you are on.
    public init(axes: [String: [String]], state: ViewState, action: String) {
        self.axes = axes
        self.state = state
        self.action = action
    }

    /// The document's theme axes and their values.
    public let axes: [String: [String]]

    /// The current view state.
    public let state: ViewState

    /// The path the form submits to.
    public let action: String

    public var body: some HTML {
        // A file with no theme axes — and every page with no file — shows no control
        // rather than a label saying there is nothing to control, and no wrapper either:
        // an empty `div` is still a flex item, and the bar's `gap` counted it.
        if !axes.isEmpty {
            div(.class("v-theme")) {
                for axis in axes.keys.sorted() {
                    AxisPicker(
                        axis: axis,
                        values: axes[axis] ?? [],
                        state: state,
                        action: action
                    )
                }
            }
        }
    }

    /// One axis's dropdown.
    struct AxisPicker: HTML {
        /// The axis's name.
        let axis: String

        /// The values it can take.
        let values: [String]

        /// The current view state.
        let state: ViewState

        /// The path the form submits to.
        let action: String

        /// The complete `?theme=` value this axis would produce for one of its values.
        ///
        /// - Parameter value: The value to pin, or `nil` for the document's default.
        /// - Returns: The canonical pin set.
        func pinned(_ value: String?) -> String {
            ThemeQuery.canonical(state.pinning(axis, to: value).theme)
        }

        var body: some HTML {
            form(.class("v-theme-axis"), .method(.get), .action(action)) {
                if let node = state.node {
                    input(.type(.hidden), .name("node"), .value(node))
                }
                if let depth = state.depth {
                    input(.type(.hidden), .name("depth"), .value(String(depth)))
                }
                if let follow = state.follow.query {
                    input(.type(.hidden), .name("follow"), .value(follow))
                }
                label(.class("v-theme-label"), .for("v-theme-\(axis)")) { "\(axis):" }
                select(
                    .id("v-theme-\(axis)"),
                    .class("v-theme-select"),
                    .name("theme"),
                    .data("axis", value: axis)
                ) {
                    option(.value(pinned(nil))) { "default" }
                        .attributes(.selected, when: state.theme[axis] == nil)
                    for value in values {
                        option(.value(pinned(value))) { value }
                            .attributes(.selected, when: state.theme[axis] == value)
                    }
                }
                button(.class("v-go"), .type(.submit)) { "apply" }
            }
        }
    }
}
