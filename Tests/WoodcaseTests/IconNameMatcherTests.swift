//
//  IconNameMatcherTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

struct IconNameMatcherTests {
    /// A slice of real Lucide names, small enough to reason about by hand but wide
    /// enough to exercise every tier.
    private let names = [
        "check", "check-check", "check-line", "circle-check", "circle-check-big",
        "square-check", "square-check-big", "badge-check", "book-check",
        "alarm-clock-check", "bell", "home",
    ]

    @Test("An empty query matches nothing")
    func emptyQueryMatchesNothing() {
        #expect(IconNameMatcher.matches(names, query: "") == [])
    }

    @Test("An exact match ranks first, ahead of everything containing it")
    func exactMatchRanksFirst() {
        let matched = IconNameMatcher.matches(names, query: "check")
        #expect(matched.first == "check")
    }

    @Test("A query every name contains matches exactly those names, substring tier")
    func substringMatchesEveryContainingName() {
        let matched = IconNameMatcher.matches(names, query: "check")
        #expect(Set(matched) == Set(names.filter { $0.contains("check") }))
    }

    @Test("A substring match ranks ahead of a fuzzy-only match for the same query")
    func substringRanksAboveFuzzy() {
        // "badge-check-2" contains the query outright; "book-check" only shares the
        // "check" token, with no substring relationship either way.
        let candidates = ["badge-check-2", "book-check"]
        #expect(IconNameMatcher.matches(candidates, query: "badge-check") == candidates)
    }

    @Test("A renamed icon's fuzzy match proposes the token-overlapping name first")
    func fuzzyMatchProposesTokenOverlap() {
        // "check-circle-2" is not in the table at all (Lucide renamed it to
        // "circle-check"); no tier-1/2 match exists, so this exercises the fuzzy
        // tier alone.
        let matched = IconNameMatcher.matches(names, query: "check-circle-2")
        #expect(matched.first == "circle-check")
    }

    @Test("A query unrelated to every name matches nothing")
    func unrelatedQueryMatchesNothing() {
        #expect(IconNameMatcher.matches(names, query: "xylophone-emoji-9000") == [])
    }

    @Test("limit caps the result, keeping the best matches")
    func limitCapsResults() {
        let matched = IconNameMatcher.matches(names, query: "check", limit: 2)
        #expect(matched.count == 2)
        #expect(matched.first == "check")
    }

    @Test("Matching is case-insensitive; the returned name keeps its original case")
    func caseInsensitiveMatch() {
        let matched = IconNameMatcher.matches(["Bell", "home"], query: "BELL")
        #expect(matched == ["Bell"])
    }

    @Test("Ties within a tier break alphabetically, so the order is reproducible")
    func tiesBreakAlphabetically() {
        let first = IconNameMatcher.matches(names, query: "check")
        let second = IconNameMatcher.matches(names, query: "check")
        #expect(first == second)
    }

    @Test("The Levenshtein distance between two strings is the number of edits")
    func levenshteinDistance() {
        #expect(IconNameMatcher.levenshteinDistance("check", "check") == 0)
        #expect(IconNameMatcher.levenshteinDistance("check", "chek") == 1)
        #expect(IconNameMatcher.levenshteinDistance("", "abc") == 3)
        #expect(IconNameMatcher.levenshteinDistance("abc", "") == 3)
    }
}
