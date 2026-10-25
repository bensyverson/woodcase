//
//  CRDTDocument+OverrideEntries.swift
//  Woodcase
//

import Foundation

/// An instance's overrides as replica state: one last-writer-wins register per key.
///
/// A `ref` holds two override maps — ``PenNode/RefData/descendants`` (descendant id →
/// key → value) and ``PenNode/RefData/rootOverrides`` (key → value). Replicated whole,
/// two people overriding different keys of one instance would clobber each other, so each
/// key is its own register, written as an ordinary ``CRDTOperation/SetProperty`` under an
/// *entry path*: `kind.descendants.<descendant>.<key>` or `kind.rootOverrides.<key>`, each
/// segment escaped as metadata entry keys are (`.` → `%2E`, `%` → `%25`).
///
/// An override may hold JSON `null` — it clears the key on that instance — so an entry's
/// value cannot use `null` for "absent". A present value travels wrapped,
/// `{"value": <value>}`; ``AnyCodable/null`` removes the key. A descendant left with no
/// keys is removed, and so is an emptied map.
///
/// Every local write of a ref's maps — an override, a root override, an `updateKind`, a
/// `setProperties` naming `kind.descendants` or `kind.rootOverrides` — replicates as the
/// entries it changed, never as a whole map, so no whole-map write races an entry.
extension CRDTDocument {
    /// The prefix of a descendant override's entry paths.
    static let descendantEntryPrefix = "kind.descendants."

    /// The prefix of a root override's entry paths.
    static let rootOverrideEntryPrefix = "kind.rootOverrides."

    /// The key a present entry value is wrapped under.
    static let overrideValueKey = "value"

    /// The paths of a ref's whole override maps, which local writes never replicate.
    static let overrideMapPaths: Set<String> = ["kind.descendants", "kind.rootOverrides"]

    /// Whether a kind path is one of a ref's override maps, which replicate as entries.
    ///
    /// - Parameters:
    ///   - path: A `kind.*` path a local write changes.
    ///   - old: The node's kind before.
    ///   - new: Its kind after.
    /// - Returns: `true` for `kind.descendants` or `kind.rootOverrides` on a ref that stays one.
    static func isReplicatedByEntry(_ path: String, from old: PenNode.Kind, to new: PenNode.Kind) -> Bool {
        guard overrideMapPaths.contains(path), case .ref = old, case .ref = new else { return false }
        return true
    }

    /// Records the override entries one ref kind changes into another and returns the
    /// operations to send, sorted by path. Nothing when either kind is not a ref.
    ///
    /// - Parameters:
    ///   - nodeID: The ref.
    ///   - old: Its kind before.
    ///   - new: Its kind after.
    /// - Returns: One ``CRDTOperation/SetProperty`` per entry that differs.
    func processLocalOverrideEntries(nodeID: String, from old: PenNode.Kind, to new: PenNode.Kind) -> [CRDTOperation] {
        guard case let .ref(before) = old, case let .ref(after) = new else { return [] }
        let oldEntries = Self.overrideEntries(of: before)
        let newEntries = Self.overrideEntries(of: after)
        return Set(oldEntries.keys).union(newEntries.keys).sorted().compactMap { path in
            let value = newEntries[path] ?? .null
            guard (oldEntries[path] ?? .null) != value else { return nil }
            let op = makeOp(.setProperty(CRDTOperation.SetProperty(nodeID: nodeID, property: path, value: value)))
            propertyMaps[nodeID, default: LWWPropertyMap()].record(property: path, at: op.id)
            return op
        }
    }

    /// A ref's overrides as entries: each entry path and its wrapped value.
    static func overrideEntries(of ref: PenNode.RefData) -> [String: AnyCodable] {
        var entries: [String: AnyCodable] = [:]
        for (descendant, override) in ref.descendants ?? [:] {
            for (key, value) in override.properties {
                entries[descendantEntryPath(descendant, key)] = .dictionary([overrideValueKey: value])
            }
        }
        for (key, value) in ref.rootOverrides ?? [:] {
            entries[rootOverrideEntryPrefix + escaped(key)] = .dictionary([overrideValueKey: value])
        }
        return entries
    }

    /// A node with one override entry written, or `nil` when `path` is not an entry path.
    /// A malformed value, or a node that is not a ref, leaves the node as it was.
    ///
    /// - Parameters:
    ///   - value: The entry's wrapped value, or ``AnyCodable/null`` to remove it.
    ///   - path: The entry path.
    ///   - node: The node to write.
    /// - Returns: The written node, or `nil` for a path that names no entry.
    static func settingOverrideEntry(_ value: AnyCodable, at path: String, on node: PenNode) -> PenNode? {
        let target: (descendant: String?, key: String)
        if path.hasPrefix(descendantEntryPrefix) {
            let segments = segments(of: path.dropFirst(descendantEntryPrefix.count))
            guard segments.count == 2 else { return nil }
            target = (segments[0], segments[1])
        } else if path.hasPrefix(rootOverrideEntryPrefix) {
            let segments = segments(of: path.dropFirst(rootOverrideEntryPrefix.count))
            guard segments.count == 1 else { return nil }
            target = (nil, segments[0])
        } else {
            return nil
        }
        guard case var .ref(ref) = node.kind else { return node }
        let written: AnyCodable?
        switch value {
        case .null: written = nil
        case let .dictionary(wrapper) where wrapper.count == 1 && wrapper[overrideValueKey] != nil:
            written = wrapper[overrideValueKey]
        default: return node
        }
        if let descendant = target.descendant {
            var descendants = ref.descendants ?? [:]
            var properties = descendants[descendant]?.properties ?? [:]
            properties[target.key] = written
            descendants[descendant] = properties.isEmpty ? nil : PenDescendantOverride(properties: properties)
            ref.descendants = descendants.isEmpty ? nil : descendants
        } else {
            var overrides = ref.rootOverrides ?? [:]
            overrides[target.key] = written
            ref.rootOverrides = overrides.isEmpty ? nil : overrides
        }
        var patched = node
        patched.kind = .ref(ref)
        return patched
    }

    /// The entry path of one key of one descendant's override.
    static func descendantEntryPath(_ descendant: String, _ key: String) -> String {
        descendantEntryPrefix + escaped(descendant) + "." + escaped(key)
    }

    /// A path segment with `%` and `.` escaped.
    private static func escaped(_ segment: String) -> String {
        segment.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: ".", with: "%2E")
    }

    /// The unescaped segments of an entry path's tail; empty when one is empty.
    private static func segments(of tail: Substring) -> [String] {
        let segments = tail.split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.removingPercentEncoding ?? String($0) }
        return segments.contains(where: \.isEmpty) ? [] : segments
    }
}
