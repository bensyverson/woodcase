//
//  PenNoteBoard+Identity.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// What an identity filter's value is to this file.
    enum IdentityCheck: Friendly {
        /// An identity the file names, without the `@` it may have been written with.
        case known(String)
        /// A name the file does not hold and nothing it holds is close to; a filter on it
        /// keeps nothing, which is an answer, not a mistake.
        case unknown(String, known: [String])
    }

    /// Every identity the file names: note, comment and prompt authors, everyone a
    /// comment mentions, and everyone who requested a run — each once, sorted.
    var identities: [String] {
        var names: Set<String> = []
        names.formUnion(notes.compactMap(\.author))
        names.formUnion(threads.flatMap(\.authors))
        names.formUnion(threads.flatMap(\.mentions))
        names.formUnion(prompts.compactMap(\.author))
        names.formUnion(prompts.compactMap(\.requestedBy))
        return names.sorted()
    }

    /// Checks an identity filter's value against the identities the file names.
    ///
    /// Identities match exactly, case included, as `--as` writes them. A value that is
    /// not one, but is close to one — a different case, or within two slips, a swap of
    /// neighboring letters counting as one — is
    /// refused as a misspelling: listing nothing would read as "nothing for you" when the
    /// truth is "you mistyped". A value nothing is close to is ``IdentityCheck/unknown(_:known:)``
    /// and filters to nothing: an agent polling for its first mention is not wrong.
    ///
    /// - Parameters:
    ///   - value: The value given; a leading `@` is dropped, as a mention writes one.
    ///   - option: The flag it was given to, for the refusal.
    /// - Returns: Whether the name is one the file holds.
    /// - Throws: ``FilterError/misspelledIdentity(option:value:suggestion:known:)``.
    func identity(_ value: String, for option: String) throws -> IdentityCheck {
        let name = value.hasPrefix("@") ? String(value.dropFirst()) : value
        let known = identities
        if known.contains(name) { return .known(name) }
        let needle = name.lowercased()
        let closest = known
            .map { (name: $0, distance: Self.typoDistance(needle, $0.lowercased())) }
            .filter { $0.distance <= 2 }
            .min { $0.distance < $1.distance }
        if let closest {
            throw FilterError.misspelledIdentity(option: option, value: value, suggestion: closest.name, known: known)
        }
        return .unknown(name, known: known)
    }

    /// The number of single-letter slips between two names — an insert, a delete, a
    /// substitution, or a swap of neighbors — so `bne` is one slip from `ben` and two
    /// from `ana` (optimal string alignment distance).
    private static func typoDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0 ... a.count {
            table[i][0] = i
        }
        for j in 0 ... b.count {
            table[0][j] = j
        }
        for i in 1 ... a.count {
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
