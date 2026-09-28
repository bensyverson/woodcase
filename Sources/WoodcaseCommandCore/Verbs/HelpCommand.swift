//
//  HelpCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

/// `woodcase help [<topic>|<verb>…]` — the things the verbs assume, and the verbs.
///
/// Help never has preconditions: this verb opens no file, takes no lock and reads no
/// environment, so it answers on a machine where nothing is set up yet. That is the
/// whole point of a topic — an agent reads ``HelpTopic/design`` before it has a
/// document to read.
///
/// It also stands in front of ArgumentParser's own `help` subcommand, which a
/// user-declared `help` shadows in the command tree. Everything that command did still
/// works — `woodcase help tree`, `woodcase help vars set` — because a subject that is
/// not a topic is looked up as a verb and rendered with
/// `ParsableCommand.helpMessage(for:)`.
struct Help: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "help",
        abstract: "Explain what every verb assumes, or print one verb's help.",
        discussion: """
        A topic explains the format itself — what a verb's own --help has to assume. \
        With no argument, the topics are listed.

        Anything that is not a topic is looked up as a verb, so `woodcase help tree` \
        and `woodcase help vars set` print those verbs' help.

          woodcase help design
          woodcase help schema text
        """
    )

    /// The topic, or the path of words naming a verb. Empty lists the topics.
    @Argument(
        help: ArgumentHelp(
            "A topic (\(HelpTopic.allCases.map(\.rawValue).joined(separator: ", "))), "
                + "or a verb. Omit to list the topics.",
            valueName: "topic|verb"
        )
    )
    var subject: [String] = []

    /// Prints the topic, the verb's help, or the list of topics.
    func run() throws {
        guard let first = subject.first else {
            print(Self.topicList)
            return
        }
        // The one topic that takes an argument: `help schema text` is the schema verb's
        // answer, reached the way an agent that has only read the primer would reach it.
        if first == HelpTopic.schema.rawValue, subject.count <= 2 {
            try print(SchemaHelp.text(for: subject.dropFirst().first))
            return
        }
        if subject.count == 1, let topic = HelpTopic(rawValue: first) {
            print(topic.body)
            return
        }
        guard let command = Self.verb(named: subject) else {
            throw CommandFailure(message: Self.unknown(subject), exitCode: .usage)
        }
        print(WoodcaseCommand.helpMessage(for: command))
    }

    // MARK: - The list

    /// Every topic, one row each, and where to go for a verb.
    static var topicList: String {
        let width = HelpTopic.allCases.map(\.rawValue.count).max() ?? 0
        let rows = HelpTopic.allCases.map { topic in
            "  \(topic.rawValue.padding(toLength: width, withPad: " ", startingAt: 0))  \(topic.summary)"
        }
        return """
        Topics — what every verb assumes, explained once, with no file needed:

        \(rows.joined(separator: "\n"))

          woodcase help design
          woodcase help schema text

        For one verb: `woodcase help tree`, or `woodcase tree --help` — each carries a
        worked example. `woodcase` on its own prints the primer.
        """
    }

    // MARK: - Verbs

    /// The subcommand a path of words names, walking down from the root command.
    ///
    /// - Parameter path: The words after `help`, as typed (`["vars", "set"]`).
    /// - Returns: The subcommand they name, or `nil` if any word names nothing.
    static func verb(named path: [String]) -> ParsableCommand.Type? {
        var candidates = WoodcaseCommand.configuration.subcommands
        var found: ParsableCommand.Type?
        for word in path {
            guard let match = candidates.first(where: { name(of: $0) == word }) else { return nil }
            found = match
            candidates = match.configuration.subcommands
        }
        return found
    }

    /// The name a subcommand answers to on the command line.
    ///
    /// ArgumentParser derives an unnamed command's name from its type, so this has to
    /// as well. Every verb here is either explicitly named or a single word, which is
    /// why lowercasing is enough.
    private static func name(of command: ParsableCommand.Type) -> String {
        command.configuration.commandName ?? String(describing: command).lowercased()
    }

    /// The refusal for a subject that is neither a topic nor a verb.
    private static func unknown(_ subject: [String]) -> String {
        let topics = HelpTopic.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        \(subject.joined(separator: " ")) is neither a help topic nor a verb — \
        run `woodcase help` to list the topics (\(topics)), or `woodcase --help` to list the verbs.
        """
    }
}
