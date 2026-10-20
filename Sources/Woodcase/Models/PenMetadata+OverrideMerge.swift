//
//  PenMetadata+OverrideMerge.swift
//  Woodcase
//

import Foundation

/// How an instance's metadata meets its component's: per entry, never as one value.
///
/// An override of a Woodcase-owned key lives in the override's own `metadata.woodcase`
/// (`descendants[<id>].metadata.woodcase.strokeDash`), and the instance root's in the
/// `ref` node's own (Ben's ruling, 2026-10-20; rule 6 of
/// `project/2026-10-20-natural-paths-for-woodcase-properties.md`). Expansion lays each over
/// the component node's metadata key by key, so the component's notes and other Woodcase
/// keys still reach the instance, and later edits to them still flow through. Pen drops
/// both (pen CLI 0.3.11, leaf 9Sw8C0), which Ben accepts: transfers run Pen to Penumbra.
public extension PenMetadata {
    /// A component node's metadata with an override's metadata laid over it.
    ///
    /// Each top-level key of the override replaces the component's, except `woodcase`,
    /// whose keys are laid over the component's one by one. A `null` removes the key it
    /// names, so an override can clear a key on the instance alone. An override that is
    /// not an object (a `null` metadata) replaces the whole value, as before.
    ///
    /// - Parameters:
    ///   - override: The override's `metadata` value.
    ///   - base: The component node's metadata, or `nil` for none.
    /// - Returns: The metadata the instance's node carries, or `null` when it holds nothing.
    static func overlaying(_ override: AnyCodable, onto base: PenMetadata?) -> AnyCodable {
        guard case let .dictionary(entries) = override else { return override }
        var merged = base?.object ?? [:]
        for (key, value) in entries {
            if key == woodcaseNamespace, case let .dictionary(keys) = value {
                let current: [String: AnyCodable] = if case let .dictionary(existing)? = merged[key] { existing } else { [:] }
                let laid = overlayingKeys(keys, onto: current)
                if laid.isEmpty { merged.removeValue(forKey: key) } else { merged[key] = .dictionary(laid) }
            } else if value == .null {
                merged.removeValue(forKey: key)
            } else {
                merged[key] = value
            }
        }
        return merged.isEmpty ? .null : .dictionary(merged)
    }

    /// A component root's metadata with a `ref` node's `metadata.woodcase` laid over it key
    /// by key: what an instance root carries (``PenRefExpander``). Only the namespace is laid
    /// over; the ref's other metadata is its own.
    ///
    /// - Parameters:
    ///   - component: The component root's metadata, or `nil` for none.
    ///   - ref: The `ref` node's metadata, or `nil` for none.
    /// - Returns: The root's metadata, or `nil` when it holds nothing.
    static func instanceRoot(of component: PenMetadata?, under ref: PenMetadata?) -> PenMetadata? {
        guard case let .dictionary(keys)? = ref?.extensions[woodcaseNamespace], !keys.isEmpty else { return component }
        let laid = overlaying(.dictionary([woodcaseNamespace: .dictionary(keys)]), onto: component)
        guard case let .dictionary(object) = laid else { return nil }
        return PenMetadata(object: object)
    }

    /// Keys laid over keys: a `null` removes one.
    private static func overlayingKeys(
        _ keys: [String: AnyCodable], onto current: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        var laid = current
        for (key, value) in keys {
            if value == .null { laid.removeValue(forKey: key) } else { laid[key] = value }
        }
        return laid
    }
}
