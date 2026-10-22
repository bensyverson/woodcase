//
//  DictionaryOrderings.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Dictionaries of equal content that iterate in different orders.
///
/// A Swift dictionary iterates in bucket order: where each key's hash lands for the
/// dictionary's bucket count, and, for two keys that collide, the order they were
/// inserted. So the same entries built at several capacities and in every insertion
/// order iterate in several orders within one process — the way two processes, each
/// seeding its hashes differently, would.
enum DictionaryOrderings {
    /// One dictionary per distinct iteration order the entries can be built in.
    ///
    /// - Parameter entries: The entries, keys distinct.
    /// - Returns: The dictionaries, each holding exactly `entries`, no two iterating their
    ///   keys in the same order; sorted by that order, so a test walks them the same way
    ///   on every run.
    static func distinct(_ entries: [(String, AnyCodable)]) -> [[String: AnyCodable]] {
        let capacities = [0] + (0 ... 14).map { 1 << $0 }
        var found: [[String]: [String: AnyCodable]] = [:]
        for capacity in capacities {
            for order in permutations(of: entries) {
                var map = [String: AnyCodable](minimumCapacity: capacity)
                for (key, value) in order {
                    map[key] = value
                }
                let keys = Array(map.keys)
                if found[keys] == nil { found[keys] = map }
            }
        }
        return found.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map(\.value)
    }

    /// Every ordering of `elements`.
    private static func permutations<Element>(of elements: [Element]) -> [[Element]] {
        guard let first = elements.first else { return [[]] }
        return permutations(of: Array(elements.dropFirst())).flatMap { rest in
            (0 ... rest.count).map { index in
                var ordering = rest
                ordering.insert(first, at: index)
                return ordering
            }
        }
    }
}
