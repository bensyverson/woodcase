//
//  SlotFillLocation.swift
//  Woodcase
//

import Foundation

/// Where a slot's fill is stored, from the outermost instance down.
///
/// Every fill an instance shows is written on that instance's `ref` node, the one stored
/// node it has. A slot of the component it places, or of a component nested in it, is
/// one key of its `descendants` map (`List`, `PScr/List` — the key the expansion applies).
/// A slot of an instance that sits *inside a fill* is not: Pen lets no key of the outer
/// instance reach content it wrote itself (`project/2026-09-26-slot-override-keys.md`,
/// rule 5), so that fill is written on the inner instance's own JSON, inside the outer
/// fill. A location is the outer key, then one ``Hop`` per fill it steps into — the key
/// whose `children` hold an instance, and that instance's id — then the key of the slot.
struct SlotFillLocation: Friendly {
    /// One step into a fill: the key whose `children` hold an instance, and the instance.
    struct Hop: Friendly {
        /// The key, in the map the step starts from, whose `children` hold the instance.
        var key: String

        /// The instance's id, as the fill writes it.
        var refID: String
    }

    /// A `descendants` map in the form a plan rewrites: key → the entry's raw properties.
    typealias Entries = [String: [String: AnyCodable]]

    /// The stored `ref` node the fill is written on.
    var refID: String

    /// The fills stepped into, outermost first; empty for a key of ``refID``'s own map.
    var hops: [Hop] = []

    /// The slot frame's key in the map the hops end at.
    var key: String

    /// The location of a slot of an instance inside this location's fill.
    ///
    /// - Parameters:
    ///   - instanceID: The instance's id, as this fill writes it.
    ///   - key: The slot frame's key in that instance's own map.
    func entering(instance instanceID: String, key: String) -> SlotFillLocation {
        SlotFillLocation(refID: refID, hops: hops + [Hop(key: self.key, refID: instanceID)], key: key)
    }

    // MARK: - Reading

    /// The fill this location holds in a map, or `nil` when it holds none — the slot
    /// shows its default content.
    ///
    /// - Parameter entries: The stored ref's `descendants`, as entries.
    func fill(in entries: Entries) -> [AnyCodable]? {
        guard let map = Self.map(at: hops[...], in: entries),
              case let .array(children)? = map[key]?[SlotJSON.childrenKey]
        else { return nil }
        return children
    }

    // MARK: - Writing

    /// Writes this location's fill, or removes it for `nil`.
    ///
    /// - Parameters:
    ///   - children: The fill's new content; `nil` removes the fill, so the default shows.
    ///   - entries: The stored ref's `descendants`, rewritten in place.
    /// - Returns: `false` when a hop names an instance its fill does not hold.
    @discardableResult
    func setFill(_ children: [AnyCodable]?, in entries: inout Entries) -> Bool {
        modifyMap(in: &entries) { map in
            var entry = map[key] ?? [:]
            if let children {
                entry[SlotJSON.childrenKey] = .array(children)
            } else {
                entry.removeValue(forKey: SlotJSON.childrenKey)
            }
            if entry.isEmpty {
                map.removeValue(forKey: key)
            } else {
                map[key] = entry
            }
        }
    }

    /// Rewrites the map this location's key lives in.
    ///
    /// - Parameters:
    ///   - entries: The stored ref's `descendants`, rewritten in place.
    ///   - body: Changes the map.
    /// - Returns: `false` when a hop names an instance its fill does not hold.
    @discardableResult
    func modifyMap(in entries: inout Entries, _ body: (inout Entries) -> Void) -> Bool {
        Self.modify(at: hops[...], in: &entries, body)
    }

    // MARK: - Maps inside fills

    /// The map a run of hops ends at.
    private static func map(at hops: ArraySlice<Hop>, in entries: Entries) -> Entries? {
        guard let hop = hops.first else { return entries }
        guard case let .array(list)? = entries[hop.key]?[SlotJSON.childrenKey],
              let instance = SlotJSON.node(hop.refID, in: list)
        else { return nil }
        return map(at: hops.dropFirst(), in: descendantEntries(of: instance))
    }

    /// Rewrites the map a run of hops ends at.
    private static func modify(
        at hops: ArraySlice<Hop>,
        in entries: inout Entries,
        _ body: (inout Entries) -> Void
    ) -> Bool {
        guard let hop = hops.first else {
            body(&entries)
            return true
        }
        guard case var .array(list)? = entries[hop.key]?[SlotJSON.childrenKey] else { return false }
        var found = false
        SlotJSON.replace(hop.refID, in: &list) { instance in
            var inner = descendantEntries(of: instance)
            found = modify(at: hops.dropFirst(), in: &inner, body)
            if inner.isEmpty {
                instance.removeValue(forKey: SlotJSON.descendantsKey)
            } else {
                instance[SlotJSON.descendantsKey] = .dictionary(inner.mapValues { AnyCodable.dictionary($0) })
            }
        }
        entries[hop.key]?[SlotJSON.childrenKey] = .array(list)
        return found
    }

    /// The `descendants` map an instance's JSON carries, as entries.
    static func descendantEntries(of instance: [String: AnyCodable]) -> Entries {
        guard case let .dictionary(map)? = instance[SlotJSON.descendantsKey] else { return [:] }
        return map.compactMapValues { value in
            guard case let .dictionary(entry) = value else { return nil }
            return entry
        }
    }
}
