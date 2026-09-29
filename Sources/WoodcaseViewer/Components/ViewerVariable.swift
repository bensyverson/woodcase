//
//  ViewerVariable.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One row of the variables section: a token, what it is worth, and who touched it last.
///
/// Tokens are what agents contend over — two of them changing `accent` is the collision
/// the viewer exists to make visible — so a variable carries the same attribution an
/// outline row does.
///
/// ## Attribution comes from the log's inverse operations
///
/// An ``ActivityEvent`` for a variable change records **no node ids**: variables are not
/// nodes. What it does record is the inverse operation, and the inverse of a variable
/// write names the variable. That is where ``lastEditor`` comes from.
public struct ViewerVariable: Friendly, Identifiable {
    /// One themed variant of a variable: the axis pins that select it, its value, and —
    /// for a color variable — the swatch to draw beside that value.
    ///
    /// Nested rather than filed on its own: it has no use outside a ``ViewerVariable``,
    /// and it exists to give the expanded table one strongly-typed row instead of a
    /// hand-formatted string a view would have to reparse.
    public struct Variant: Friendly {
        /// Creates a variant row.
        ///
        /// - Parameters:
        ///   - axis: How the variant's axis pins read — `mode=light`, or `*` for the
        ///     variant that applies unconditionally.
        ///   - value: The variant's value, described as text.
        ///   - swatch: A `#RRGGBB` color to draw beside the value, when the owning
        ///     variable is a color.
        public init(axis: String, value: String, swatch: String? = nil) {
            self.axis = axis
            self.value = value
            self.swatch = swatch
        }

        /// How the variant's axis pins read — `mode=light`, or `*` for the variant that
        /// applies unconditionally.
        public let axis: String

        /// The variant's value, described as text.
        public let value: String

        /// A `#RRGGBB` color to draw beside the value, when the owning variable is a
        /// color.
        public let swatch: String?
    }

    /// Creates a variable row.
    ///
    /// - Parameters:
    ///   - name: The variable's name, as `$name` refers to it.
    ///   - type: Its declared type.
    ///   - value: Its value under the current theme, as text.
    ///   - swatch: A `#RRGGBB` color to draw beside it, when the value is a color.
    ///   - variants: Its themed variants, oldest declared first.
    ///   - lastEditor: The identity that last wrote it, when the log says.
    ///   - lastChange: When that write happened.
    public init(
        name: String,
        type: PenVariableType,
        value: String,
        swatch: String? = nil,
        variants: [Variant] = [],
        lastEditor: String? = nil,
        lastChange: Date? = nil
    ) {
        self.name = name
        self.type = type
        self.value = value
        self.swatch = swatch
        self.variants = variants
        self.lastEditor = lastEditor
        self.lastChange = lastChange
    }

    /// The variable's name, which is also its id in the section.
    public var id: String {
        name
    }

    /// The variable's name, as `$name` refers to it.
    public let name: String

    /// Its declared type.
    public let type: PenVariableType

    /// Its value under the current theme, as text.
    public let value: String

    /// A `#RRGGBB` color to draw beside it, when the value is a color.
    public let swatch: String?

    /// Its themed variants, oldest declared first.
    public let variants: [Variant]

    /// The identity that last wrote it, when the log says.
    public let lastEditor: String?

    /// When that write happened.
    public let lastChange: Date?

    /// The rows for a document, sorted by name.
    ///
    /// - Parameters:
    ///   - document: The document to read. Variables survive resolution, so either the
    ///     parsed or the resolved form answers the same.
    ///   - theme: The theme axes pinned for this view, which decide which variant reads
    ///     as *the* value.
    ///   - events: Recent activity for this file, oldest first, for attribution.
    /// - Returns: One row per variable, sorted by name.
    public static func rows(
        of document: PenDocument,
        theme: [String: String],
        events: [ActivityEvent] = []
    ) -> [ViewerVariable] {
        let attribution = attribution(in: events)
        return (document.variables ?? [:]).keys.sorted().compactMap { name in
            guard let variable = document.variables?[name] else { return nil }
            let credited = attribution[name]
            return ViewerVariable(
                name: name,
                type: variable.type,
                value: text(of: variable, theme: theme),
                swatch: variable.type == .color ? text(of: variable, theme: theme) : nil,
                variants: variants(of: variable),
                lastEditor: credited?.identity,
                lastChange: credited?.time
            )
        }
    }

    /// Who last wrote each variable, from the log's inverse operations.
    ///
    /// - Parameter events: The file's events, oldest first.
    /// - Returns: The most recent writer of each variable, by variable name.
    static func attribution(in events: [ActivityEvent]) -> [String: (identity: String, time: Date)] {
        var credited: [String: (identity: String, time: Date)] = [:]
        for event in events where event.op == .var {
            for operation in event.inverse {
                guard let name = variableName(of: operation) else { continue }
                credited[name] = (event.identity, event.time)
            }
        }
        return credited
    }

    /// The variable a variable operation names.
    static func variableName(of operation: EditOperation) -> String? {
        switch operation {
        case let .addVariable(op): op.name
        case let .updateVariable(op): op.name
        case let .removeVariable(op): op.name
        default: nil
        }
    }

    /// The value a variable takes under a theme.
    ///
    /// The resolver's own rule: the last themed variant whose conditions the theme
    /// satisfies wins, and a variant with no conditions is the fallback.
    static func text(of variable: PenVariable, theme: [String: String]) -> String {
        switch variable.value {
        case let .simple(value):
            describe(value)
        case let .themed(values):
            describe(
                values.last { variant in
                    (variant.theme ?? [:]).allSatisfy { theme[$0.key] == $0.value }
                }?.value ?? values.last?.value
            )
        }
    }

    /// A variable's themed variants, oldest declared first.
    ///
    /// - Parameter variable: The variable whose variants to read.
    /// - Returns: One row per themed variant, each carrying a swatch when the variable
    ///   is a color. A variable with a simple (unthemed) value has none — its one value
    ///   already reads in the summary row, with nothing to tabulate beside it.
    static func variants(of variable: PenVariable) -> [Variant] {
        guard case let .themed(values) = variable.value else { return [] }
        return values.map { variant in
            let pins = (variant.theme ?? [:]).keys.sorted()
                .map { "\($0)=\(variant.theme?[$0] ?? "")" }
                .joined(separator: " ")
            let text = describe(variant.value)
            return Variant(
                axis: pins.isEmpty ? "*" : pins,
                value: text,
                swatch: variable.type == .color ? text : nil
            )
        }
    }

    /// A codable value, as the shortest text that still says what it is.
    static func describe(_ value: AnyCodable?) -> String {
        switch value {
        case .none, .some(.null): "—"
        case let .some(.string(text)): text
        case let .some(.bool(flag)): flag ? "true" : "false"
        case let .some(.int(number)): String(number)
        case let .some(.double(number)): OutlineRow.number(number)
        case let .some(.array(items)): items.map { describe($0) }.joined(separator: ", ")
        case let .some(.dictionary(pairs)):
            "{" + pairs.keys.sorted().map { "\($0): \(describe(pairs[$0]))" }.joined(separator: ", ") + "}"
        }
    }
}
