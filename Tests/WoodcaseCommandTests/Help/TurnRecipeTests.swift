//
//  TurnRecipeTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// The recipes topic's "taking turns" loop does what its comments say: the agent's
/// second look lists the person's copy edit and post-it, not its own write, and the
/// `--wait` that follows returns at once on the person's next edit.
@Suite("`help recipes` taking turns")
struct TurnRecipeTests {
    @Test("The edit, react and resume loop lists the other writer's changes with new values")
    func editReactResume() throws {
        let commands = RecipesTests.extractCommands(from: HelpTopic.recipes.body)
        let looks = commands.indices.filter { commands[$0].arguments.first == "changes" }
        #expect(looks.count == 3, "the recipe should look three times: first, after the reaction, and --wait")
        guard looks.count == 3 else { return }

        let fixture = try CommandFixture(fixture: "batch.pen")
        var outputs: [Int: CommandRun] = [:]
        for (index, command) in commands.enumerated() {
            let started = ContinuousClock.now
            let run = try fixture.run(command.arguments, stdin: command.stdin)
            outputs[index] = run
            if index == looks[2] {
                #expect(ContinuousClock.now - started < .seconds(30), "--wait should return on ben's edit at once")
            }
        }

        let first = try #require(outputs[looks[0]])
        let second = try #require(outputs[looks[1]])
        let third = try #require(outputs[looks[2]])
        #expect(first.stdout.contains("first look"))
        #expect(second.stdout.contains(#"ben"#))
        #expect(second.stdout.contains(#"Home/Header/Title  kind.content: "Welcome" → "Welcome back""#))
        #expect(second.stdout.contains(#"added note "Warmer, please""#))
        #expect(!second.stdoutLines.contains { $0.contains("claude") })
        #expect(third.status == 0)
        #expect(third.stdout.contains(#"common.name: "Header" → "Top""#))
        #expect(!third.stdout.contains("Welcome back!"))
    }
}
