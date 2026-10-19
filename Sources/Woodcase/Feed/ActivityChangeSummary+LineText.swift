//
//  ActivityChangeSummary+LineText.swift
//  Woodcase
//

import Foundation

extension ActivityChangeSummary {
    /// Renders one ``Change`` as its line.
    ///
    /// Values are written as compact JSON — a string quoted, a number bare — so a line
    /// reads the way `woodcase set` takes the value back. Text is never shortened: a
    /// copy edit or a post-it is the whole point of the line. An object or array value
    /// longer than ``objectLimit`` is cut with `…`; the full value is in the JSON form.
    struct LineText {
        /// Prepares a change for rendering.
        ///
        /// - Parameter change: The change.
        init(_ change: Change) {
            self.change = change
        }

        /// The line.
        var text: String {
            switch change.kind {
            case .add, .cp:
                structural { "\($0)  added \(Self.label(of: change.new))\(place(in: "in"))" }
            case .rm:
                structural { "\($0)  removed \(Self.label(of: change.old))\(place(in: "from"))" }
            case .mv:
                structural { "\($0)  moved from \(Self.where(change.old)) to \(Self.where(change.new))" }
            case .replace:
                structural { "\($0)  replaced with \(Self.label(of: change.new))" }
            case .detach:
                "\(subject)  detached from its component"
            case .override:
                change.key.map { key in
                    let target = change.descendant.map { " \($0)" } ?? ""
                    return "\(subject)  override\(target) \(key): \(transition)"
                } ?? subject
            case .var, .import, .theme:
                change.key.map { "\(change.kind.rawValue) \($0): \(transition)" } ?? subject
            case .external:
                "changed outside woodcase — re-read the file"
            case .migrate:
                "rewritten in the current format"
            case .new:
                "created"
            case .set, .place, .undo, .redo, .merge:
                change.key.map { "\(change.node == nil ? "document" : subject)  \($0): \(transition)" } ?? subject
            }
        }

        /// The longest an object or array value is printed before it is cut.
        static let objectLimit = 120

        // MARK: - Private

        private let change: Change

        /// The node the line is about: its path, else its id, else `-`.
        private var subject: String {
            change.path ?? change.node ?? "-"
        }

        /// `old → new`, naming an absent side.
        private var transition: String {
            "\(Self.value(change.old) ?? "(none)") → \(Self.value(change.new) ?? "(removed)")"
        }

        /// A structural line when the change carries what it needs, else the bare subject.
        private func structural(_ body: (String) -> String) -> String {
            change.old == nil && change.new == nil ? subject : body(subject)
        }

        /// ` in Home at 2`: where a node went or came from.
        private func place(in preposition: String) -> String {
            let parent = " \(preposition) \(change.parent ?? "the document")"
            return parent + (change.index.map { " at \($0)" } ?? "")
        }

        /// `Home at 2` from a moved node's `{parent, index}`.
        private static func `where`(_ value: AnyCodable?) -> String {
            guard case let .dictionary(place) = value else { return "?" }
            let parent = if case let .string(name) = place["parent"] { name } else { "the document" }
            let index = if case let .int(index) = place["index"] { " at \(index)" } else { "" }
            return parent + index
        }

        /// `text "Warmer, please"`: a node's type and its text, else its name.
        private static func label(of node: AnyCodable?) -> String {
            guard case let .dictionary(object) = node else { return "node" }
            let type = if case let .string(type) = object["type"] { type } else { "node" }
            for key in ["content", "name"] {
                if case let .string(text) = object[key], let quoted = value(.string(text)) {
                    return "\(type) \(quoted)"
                }
            }
            return type
        }

        /// A value as compact JSON, or `nil` for an absent one.
        private static func value(_ value: AnyCodable?) -> String? {
            guard let value else { return nil }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(value) else { return "?" }
            let text = String(decoding: data, as: UTF8.self)
            switch value {
            case .array where text.count > objectLimit, .dictionary where text.count > objectLimit:
                return text.prefix(objectLimit - 1) + "…"
            default:
                return text
            }
        }
    }
}
