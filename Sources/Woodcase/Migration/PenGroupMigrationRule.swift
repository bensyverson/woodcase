//
//  PenGroupMigrationRule.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Drops a group's layout and sizing properties on the way to the 2.17 shape.
///
/// Pen 2.17 makes `group` a transparent container — `Entity + children +
/// effects` only, per ``PenNode/GroupData``. A legacy `group` may still carry
/// the flex-container properties a group used to lay out its own children
/// with: `layout`, `gap`, `padding`, `justifyContent`, `alignItems`, `width`
/// and `height`. The 2.17 model positions a group's children absolutely, at
/// their own x/y, and sizes the group as their union (``PenLayoutEngine``),
/// so these keys have nowhere to go and are deleted.
///
/// A dropped value that already matched the property's old default —
/// `layout: "none"`, `gap: 0`, `padding: 0`, `justifyContent`/`alignItems:
/// "start"`, `width`/`height: "fit_content"` — changes nothing observable, so
/// it is removed silently. Anything else is a genuine loss: a real layout
/// choice, a nonzero gap or padding, an explicit width or height. The rule
/// emits one diagnostic per node naming every key it actually discarded.
public struct PenGroupMigrationRule: PenMigrationRule {
    /// Creates the rule.
    public init() {}

    /// The 2.11 shape: only a legacy (2.8 – 2.10) document gets this rule.
    public let target = PenFormatVersion.oldestModern

    /// The keys this rule removes from every `group` node.
    private static let keys = [
        "layout", "gap", "padding", "justifyContent", "alignItems", "width", "height",
    ]

    /// Removes the legacy layout/size keys from a `group` node, reporting the ones
    /// that carried a non-default value.
    public func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
        guard node["type"] == .string("group") else { return }

        var discarded: [String] = []
        for key in Self.keys {
            guard let value = node.removeValue(forKey: key) else { continue }
            if !Self.isDefault(key: key, value: value) {
                discarded.append(key)
            }
        }

        guard !discarded.isEmpty else { return }
        diagnostics?.warn(
            "Dropped group layout properties no longer supported in 2.17: \(discarded.joined(separator: ", "))",
            stage: .migration,
            nodeID: id
        )
    }

    /// Whether a removed key's raw JSON value is the property's old default —
    /// dropping it changes nothing observable.
    private static func isDefault(key: String, value: AnyCodable) -> Bool {
        switch key {
        case "layout": value == .string("none")
        case "gap", "padding": isZero(value)
        case "justifyContent", "alignItems": value == .string("start")
        case "width", "height": value == .string("fit_content")
        default: false
        }
    }

    /// Whether a gap/padding value is entirely zero — a single number, or every
    /// element of a 2- or 4-element padding array is.
    private static func isZero(_ value: AnyCodable) -> Bool {
        switch value {
        case let .int(v): v == 0
        case let .double(v): v == 0
        case let .array(values): values.allSatisfy(isZero)
        default: false
        }
    }
}
