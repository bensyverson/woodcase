//
//  PenMarkdownInline+Tokens.swift
//  Woodcase
//

import Foundation

extension PenMarkdownInline {
    /// Splits the line into text, escapes, delimiter runs and mentions.
    ///
    /// A code span — a backtick run and the next run of the same length — is text, so
    /// nothing inside it is emphasis or a mention.
    ///
    /// - Parameter units: The source.
    /// - Returns: The tokens in order, and the delimiter runs they point at.
    func tokenize(_ units: [UInt16]) -> ([Token], [Delimiter]) {
        var tokens: [Token] = []
        var delimiters: [Delimiter] = []
        var textStart = range.lowerBound
        var index = range.lowerBound
        let end = range.upperBound

        func push(_ token: Token, from start: Int, to next: Int) {
            if textStart < start { tokens.append(.text(textStart ..< start)) }
            tokens.append(token)
            index = next
            textStart = next
        }

        while index < end {
            let unit = units[index]
            switch unit {
            case PenMarkdownUnit.backslash where index + 1 < end && Self.isASCIIPunctuation(units[index + 1]):
                push(.escape(index ..< index + 2), from: index, to: index + 2)
            case PenMarkdownUnit.backtick:
                let count = runLength(of: unit, from: index, in: units)
                index = closingCodeSpan(length: count, after: index + count, in: units) ?? index + count
            case PenMarkdownUnit.asterisk, PenMarkdownUnit.underscore:
                let count = runLength(of: unit, from: index, in: units)
                delimiters.append(delimiter(index ..< index + count, in: units))
                push(.delimiter(delimiters.count - 1), from: index, to: index + count)
            case PenMarkdownUnit.at:
                if let mention = mention(at: index, in: units) {
                    push(.mention(index ..< mention.end, name: mention.name), from: index, to: mention.end)
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        if textStart < end { tokens.append(.text(textStart ..< end)) }
        return (tokens, delimiters)
    }

    /// How many copies of `unit` run from `start`, within the line.
    private func runLength(of unit: UInt16, from start: Int, in units: [UInt16]) -> Int {
        units[start ..< range.upperBound].prefix { $0 == unit }.count
    }

    /// The end of the backtick run of exactly `length` that closes a code span, or `nil`.
    private func closingCodeSpan(length: Int, after start: Int, in units: [UInt16]) -> Int? {
        var index = start
        while index < range.upperBound {
            guard units[index] == PenMarkdownUnit.backtick else {
                index += 1
                continue
            }
            let count = runLength(of: PenMarkdownUnit.backtick, from: index, in: units)
            if count == length { return index + count }
            index += count
        }
        return nil
    }

    /// A delimiter run, with whether it may open or close emphasis by CommonMark's
    /// flanking rules: `_` neither opens nor closes inside a word.
    private func delimiter(_ run: Range<Int>, in units: [UInt16]) -> Delimiter {
        let before = scalar(before: run.lowerBound, in: units)
        let after = scalar(at: run.upperBound, in: units)?.scalar
        let leftFlanking = !Self.isWhitespace(after)
            && (!Self.isPunctuation(after) || Self.isWhitespace(before) || Self.isPunctuation(before))
        let rightFlanking = !Self.isWhitespace(before)
            && (!Self.isPunctuation(before) || Self.isWhitespace(after) || Self.isPunctuation(after))
        let character = units[run.lowerBound]
        let isUnderscore = character == PenMarkdownUnit.underscore
        return Delimiter(
            range: run,
            character: character,
            canOpen: leftFlanking && (!isUnderscore || !rightFlanking || Self.isPunctuation(before)),
            canClose: rightFlanking && (!isUnderscore || !leftFlanking || Self.isPunctuation(after)),
            remaining: run.count
        )
    }

    /// The mention an `@` at `start` opens, or `nil`: the `@` must not follow a name
    /// character or another `@` (so an address is not one), and at least one name
    /// character must follow it. A trailing `.` ends a sentence, not the name.
    private func mention(at start: Int, in units: [UInt16]) -> (end: Int, name: String)? {
        let before = scalar(before: start, in: units)
        if let before, Self.isNameCharacter(before) || before == "@" { return nil }
        var end = start + 1
        while let next = scalar(at: end, in: units), Self.isNameCharacter(next.scalar) {
            end += next.width
        }
        while end > start + 1, units[end - 1] == PenMarkdownUnit.period {
            end -= 1
        }
        guard end > start + 1 else { return nil }
        return (end, String(decoding: units[start + 1 ..< end], as: UTF16.self))
    }
}
