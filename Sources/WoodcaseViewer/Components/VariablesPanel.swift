//
//  VariablesPanel.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The variables section beneath the outline: name, value or swatch, last editor, age.
///
/// It is here rather than behind a tab because tokens are what agents contend over. Two
/// agents editing different frames are working; two agents editing `accent` are about to
/// undo each other, and the only way to see that coming is to have the tokens and their
/// attribution on screen while the render is.
///
/// Also the fragment served at `GET /files/{file}/variables`.
public struct VariablesPanel: HTML {
    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - variables: The document's variables, sorted by name.
    ///   - axes: The document's theme axes and their values, for the header line.
    ///   - clock: The moment the page is rendered for.
    public init(variables: [ViewerVariable], axes: [String: [String]], clock: ViewerClock) {
        self.variables = variables
        self.axes = axes
        self.clock = clock
    }

    /// The document's variables, sorted by name.
    public let variables: [ViewerVariable]

    /// The document's theme axes and their values.
    public let axes: [String: [String]]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The axes as one line — `mode: light, dark`.
    var axesNote: String {
        axes.keys.sorted()
            .map { "\($0): \((axes[$0] ?? []).joined(separator: ", "))" }
            .joined(separator: " · ")
    }

    public var body: some HTML {
        section(.class("v-panel v-variables"), .id(ViewerLink.Fragment.variables.target)) {
            header(.class("v-panel-head")) {
                div(.class("v-panel-head-title")) {
                    button(
                        .class("v-variables-toggle"),
                        .type(.button),
                        .title("Collapse or expand the variables list")
                    ) { DisclosureGlyph() }
                    h2(.class("v-panel-title")) { "Variables" }
                }
                span(.class("v-panel-note")) { axesNote }
            }
            if variables.isEmpty {
                p(.class("v-empty-note")) { "This file defines no variables." }
            } else {
                div(.class("v-variable-rows")) {
                    for variable in variables {
                        VariableRow(variable: variable, clock: clock)
                    }
                }
            }
        }
    }

    /// One variable.
    ///
    /// Nested rather than filed on its own: it has no use outside this panel, and a
    /// reader looking for how a swatch is drawn should find it here.
    struct VariableRow: HTML {
        /// The variable to draw.
        let variable: ViewerVariable

        /// The moment the page is rendered for.
        let clock: ViewerClock

        var body: some HTML {
            details(.class("v-row v-variable-row"), .data("variable", value: variable.name)) {
                summary(.class("v-variable-summary")) {
                    DisclosureGlyph()
                    if let swatch = variable.swatch {
                        span(.class("v-swatch"), .style("--v-swatch: \(swatch)"), .title(swatch)) { "" }
                    } else {
                        span(.class("v-swatch is-empty")) { "" }
                    }
                    span(.class("v-variable-name")) { variable.name }
                    VariableValue(variable: variable)
                    if let editor = variable.lastEditor {
                        AvatarView(identity: editor)
                    }
                    if let changed = variable.lastChange {
                        span(.class("v-variable-age")) { clock.age(changed, style: .compact) }
                    }
                }
                div(.class("v-variable-detail")) {
                    p(.class("v-variable-type")) { "\(variable.type.rawValue) variable" }
                    div(.class("v-variant-table")) {
                        for row in variantRows {
                            div(.class("v-variant-row")) {
                                span(.class("v-variant-axis")) { row.axis }
                                span(.class("v-variant-value")) {
                                    if let swatch = row.swatch {
                                        span(.class("v-swatch"), .style("--v-swatch: \(swatch)"), .title(swatch)) { "" }
                                    }
                                    row.value
                                }
                            }
                        }
                    }
                }
            }
        }

        /// The detail table's rows: the variable's themed variants, or — when it carries
        /// none — its one value under the current theme, so every variable expands to
        /// at least one row rather than sometimes a table and sometimes bare text.
        var variantRows: [ViewerVariable.Variant] {
            variable.variants.isEmpty
                ? [ViewerVariable.Variant(axis: "*", value: variable.value, swatch: variable.swatch)]
                : variable.variants
        }
    }

    /// A variable's value, styled by its declared type.
    ///
    /// A color already carries its meaning in the swatch beside it, so its value stays
    /// plain text; a boolean reads better as a pill than as the bare word "true", and a
    /// number gets its own class so a stylesheet can right-align or tabular-figure it
    /// without also catching every other value column.
    struct VariableValue: HTML {
        /// The variable whose value this draws.
        let variable: ViewerVariable

        var body: some HTML {
            switch variable.type {
            case .boolean:
                span(
                    .class("v-variable-value v-bool-pill"),
                    .data("value", value: variable.value)
                ) { variable.value }
            case .number:
                span(.class("v-variable-value v-variable-number")) { variable.value }
            case .string:
                span(.class("v-variable-value v-variable-string")) { variable.value }
            case .color:
                span(.class("v-variable-value")) { variable.value }
            }
        }
    }
}
