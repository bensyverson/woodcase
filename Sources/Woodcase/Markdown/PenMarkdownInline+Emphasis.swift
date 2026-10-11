//
//  PenMarkdownInline+Emphasis.swift
//  Woodcase
//

import Foundation

extension PenMarkdownInline {
    /// Matches delimiter runs into emphasis, as CommonMark's "process emphasis" does.
    ///
    /// Each closer, left to right, takes the nearest active opener of its character
    /// before it — two characters from each for strong when both have two, else one
    /// for italic — and again while both have characters left. A match deactivates the
    /// runs it encloses, and the rule of three keeps `*a**b*` from pairing the wrong
    /// runs. Characters left unmatched stay as written.
    ///
    /// - Parameter delimiters: The line's delimiter runs, updated with what each match
    ///   hid.
    /// - Returns: The matches, innermost of a run first.
    static func match(_ delimiters: inout [Delimiter]) -> [Emphasis] {
        var pairs: [Emphasis] = []
        for closer in delimiters.indices where delimiters[closer].canClose {
            while delimiters[closer].remaining > 0, delimiters[closer].isActive {
                guard let opener = delimiters[..<closer].indices.reversed().first(where: {
                    canPair(delimiters[$0], with: delimiters[closer])
                }) else { break }
                let count = delimiters[opener].remaining >= 2 && delimiters[closer].remaining >= 2 ? 2 : 1
                delimiters[opener].remaining -= count
                delimiters[opener].opening += count
                delimiters[closer].remaining -= count
                delimiters[closer].closing += count
                pairs.append(Emphasis(opener: opener, closer: closer, isStrong: count == 2))
                for enclosed in opener + 1 ..< closer {
                    delimiters[enclosed].isActive = false
                }
            }
        }
        return pairs
    }

    /// Whether `opener` may open the emphasis `closer` closes.
    private static func canPair(_ opener: Delimiter, with closer: Delimiter) -> Bool {
        guard opener.isActive, opener.canOpen, opener.remaining > 0, opener.character == closer.character else {
            return false
        }
        let lengths = (opener.range.count, closer.range.count)
        let ruleOfThree = (opener.canClose || closer.canOpen)
            && (lengths.0 + lengths.1) % 3 == 0
            && !(lengths.0 % 3 == 0 && lengths.1 % 3 == 0)
        return !ruleOfThree
    }
}
