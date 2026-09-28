//
//  RecipesTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `woodcase help recipes` must not rot: every command it shows has to still work.
///
/// This suite extracts the commands straight from ``HelpTopic/recipes``' own text and
/// runs them, in order, against one scratch file — the same file every recipe in the
/// topic builds on, exactly as an agent pasting them one after another would.
@Suite("`help recipes` stays runnable")
struct RecipesTests {
    @Test("Every command in the recipes topic exits 0, in order, against one file")
    func everyRecipeCommandExitsZero() throws {
        let commands = Self.extractCommands(from: HelpTopic.recipes.body)
        #expect(!commands.isEmpty, "no commands were extracted from the recipes topic")

        let fixture = try CommandFixture(fixture: "batch.pen")
        for (index, command) in commands.enumerated() {
            let run = try fixture.run(command.arguments, stdin: command.stdin)
            #expect(
                run.status == 0,
                """
                recipe command \(index) `woodcase \(command.arguments.joined(separator: " "))` \
                exited \(run.status): \(run.stderr)
                """
            )
        }
    }

    // MARK: - Extraction

    /// One command pulled from the topic text: its argument list, and the bytes of the
    /// heredoc it opened, if any.
    struct RecipeCommand {
        /// The command line, tokenized, with the leading `woodcase` dropped.
        let arguments: [String]
        /// The heredoc body to feed as standard input, or `nil` for a plain line.
        let stdin: Data?
    }

    /// Pulls every runnable command out of the topic's own text.
    ///
    /// A command is a line starting with two spaces then `woodcase` or `$ woodcase`.
    /// One that opens a heredoc (`<<'TAG'`) consumes every following line as its
    /// standard input, up to a line that is exactly `TAG`, flush left — the same
    /// convention a shell reads.
    ///
    /// - Parameter text: The topic body, verbatim.
    /// - Returns: Every command, in the order the topic prints them.
    static func extractCommands(from text: String) -> [RecipeCommand] {
        let lines = text.components(separatedBy: "\n")
        var commands: [RecipeCommand] = []
        var index = 0
        while index < lines.count {
            guard let commandText = commandText(in: lines[index]) else {
                index += 1
                continue
            }
            if let opened = heredoc(in: commandText) {
                var body: [String] = []
                index += 1
                while index < lines.count, lines[index] != opened.tag {
                    body.append(lines[index])
                    index += 1
                }
                index += 1 // step past the terminator line itself
                let stdin = (body + [""]).joined(separator: "\n").data(using: .utf8)
                commands.append(RecipeCommand(arguments: arguments(from: opened.command), stdin: stdin))
            } else {
                commands.append(RecipeCommand(arguments: arguments(from: commandText), stdin: nil))
                index += 1
            }
        }
        return commands
    }

    /// The text of a command line, with the leading marker stripped — or `nil` if the
    /// line is not one.
    private static func commandText(in line: String) -> String? {
        if line.hasPrefix("  $ woodcase ") {
            return String(line.dropFirst("  $ ".count))
        }
        if line.hasPrefix("  woodcase ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    /// Splits a command line at the heredoc it opens, if it opens one.
    ///
    /// - Parameter commandText: The command line, `woodcase` first.
    /// - Returns: The line with the `<<'TAG'` marker removed, and the tag to look for
    ///   as a terminator — or `nil` when the line opens no heredoc.
    private static func heredoc(in commandText: String) -> (command: String, tag: String)? {
        guard let match = commandText.firstMatch(of: /<<'([A-Za-z0-9]+)'/) else { return nil }
        let tag = String(match.1)
        let command = String(commandText[commandText.startIndex ..< match.range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        return (command, tag)
    }

    /// Tokenizes a command line and drops the leading `woodcase`.
    ///
    /// - Parameter commandText: The command line, `woodcase` first.
    /// - Returns: The arguments `CommandFixture.run(_:)` takes.
    private static func arguments(from commandText: String) -> [String] {
        Array(tokenize(commandText).dropFirst())
    }

    /// Splits a line into shell-like tokens: whitespace separates, and a single- or
    /// double-quoted span is one token with its quotes removed.
    ///
    /// This is enough for the recipes' own commands — no escaping, no nesting — not a
    /// general shell parser.
    ///
    /// - Parameter line: The text to split.
    /// - Returns: The tokens, in order.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var openQuote: Character?
        for character in line {
            if let quote = openQuote {
                if character == quote {
                    openQuote = nil
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                openQuote = character
                hasCurrent = true
            } else if character.isWhitespace {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
            } else {
                current.append(character)
                hasCurrent = true
            }
        }
        if hasCurrent {
            tokens.append(current)
        }
        return tokens
    }
}
