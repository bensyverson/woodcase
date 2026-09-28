//
//  IconNameMatcher.swift
//  Woodcase
//

import Foundation

/// Ranks icon names against a query: an exact match, then a substring match, then a
/// fuzzy match on shared name tokens or a close edit distance.
///
/// This is the one ranking `woodcase icons` prints and the `unknown-icon` lint check
/// proposes fixes from, so a query typed at a prompt and a typo caught in a document
/// are judged the same way. Matching is case-insensitive; the names returned keep
/// their original case, and ties within a tier break alphabetically, so the same
/// query against the same table always returns the same order.
public enum IconNameMatcher {
    /// Ranks `names` against `query`.
    ///
    /// The pipeline runs in three tiers, each exhausted before the next is
    /// considered:
    /// 1. **Exact** — `name` equals `query`, case-insensitively.
    /// 2. **Substring** — `name` contains `query`, case-insensitively; names closer
    ///    in length to `query` rank first. (Not the other direction: a query that
    ///    happens to embed a short, unrelated name — `"check-circle-2"` embeds
    ///    `"check"` — must not let that name outrank an actual rename in tier 3.)
    /// 3. **Fuzzy** — `name` shares at least one hyphen/underscore/space-separated
    ///    token with `query`, or sits within a small Levenshtein distance of it;
    ///    higher token overlap ranks first, then a shorter edit distance.
    ///
    /// - Parameters:
    ///   - names: The candidate names, in any order.
    ///   - query: What to rank them against. An empty query matches nothing.
    ///   - limit: The maximum number of names to return, best match first. `nil`
    ///     returns every match the pipeline finds relevant.
    /// - Returns: Matching names, best match first.
    public static func matches(_ names: [String], query: String, limit: Int? = nil) -> [String] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        let queryTokens = tokens(of: needle)

        var exact: [String] = []
        var substring: [String] = []
        var fuzzy: [(name: String, overlap: Double, distance: Int)] = []

        for name in names {
            let haystack = name.lowercased()
            if haystack == needle {
                exact.append(name)
            } else if haystack.contains(needle) {
                substring.append(name)
            } else if let scored = fuzzyScore(haystack, queryTokens: queryTokens, needle: needle) {
                fuzzy.append((name, scored.overlap, scored.distance))
            }
        }

        exact.sort()
        substring.sort(by: { closerInLength(to: needle, $0, $1) })
        fuzzy.sort {
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.name < $1.name
        }

        let ranked = exact + substring + fuzzy.map(\.name)
        guard let limit else { return ranked }
        return Array(ranked.prefix(limit))
    }

    // MARK: - Fuzzy tier

    /// The fuzzy tier's score for one candidate, or `nil` if it is not close enough
    /// to belong in the tier at all.
    ///
    /// A candidate qualifies by sharing at least one token with the query, or by
    /// sitting within a short Levenshtein distance of it — one edit for a query of
    /// six characters or fewer, two beyond that. A flat distance of two would let
    /// unrelated short words into a large table (`"clock"` is two edits from
    /// `"check"`), which token overlap does not gate at all.
    private static func fuzzyScore(
        _ haystack: String,
        queryTokens: Set<String>,
        needle: String
    ) -> (overlap: Double, distance: Int)? {
        let haystackTokens = tokens(of: haystack)
        let shared = queryTokens.intersection(haystackTokens).count
        let union = queryTokens.union(haystackTokens).count
        let overlap = union == 0 ? 0 : Double(shared) / Double(union)
        let distance = levenshteinDistance(needle, haystack)
        let bound = needle.count <= 6 ? 1 : 2
        guard shared > 0 || distance <= bound else { return nil }
        return (overlap, distance)
    }

    /// Hyphen-, underscore- and space-separated tokens, lowercased.
    private static func tokens(of name: String) -> Set<String> {
        Set(name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init))
    }

    /// Whether `a` is a better substring match than `b` for `needle`: closer in
    /// length first, alphabetical after.
    private static func closerInLength(to needle: String, _ a: String, _ b: String) -> Bool {
        let deltaA = abs(a.count - needle.count)
        let deltaB = abs(b.count - needle.count)
        if deltaA != deltaB { return deltaA < deltaB }
        return a < b
    }

    /// The Levenshtein edit distance between two strings, in single-insert/-delete/
    /// -substitute steps.
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0 ... b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            current[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}
