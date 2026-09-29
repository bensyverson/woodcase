//
//  HelpCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Help that teaches: the primer, the topics, and every verb's own screen.
///
/// `cli-design.md` asks for three things a test can hold to — a bare invocation that is
/// a primer rather than an error, help that works with no file and no setup, and one
/// worked example per verb — and this is where they are held to.
@Suite("Help that teaches")
struct HelpCommandTests {
    // MARK: - The primer

    @Test("A bare invocation is a primer, not an error")
    func bareInvocationIsAPrimer() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run([])
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        for group in ["read", "write", "render", "view"] {
            #expect(run.stdout.contains("  \(group)"), "the primer does not group the \(group) verbs")
        }
        // `serve` is listed before it is built: the primer is where an agent learns the
        // shape of the tool, and a gap there reads as "there is no viewer".
        for verb in ["tree", "get", "shot", "lint", "schema", "activity", "vars", "add", "set", "cp",
                     "mv", "rm", "override", "apply", "undo", "render", "themes", "generate",
                     "migrate", "imports", "js", "serve"]
        {
            #expect(run.stdout.contains(verb), "the primer does not list \(verb)")
        }
    }

    @Test("The primer says the one command to run first, and points at help design")
    func primerRoutesOnward() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run([])
        #expect(run.stdout.contains("woodcase tree design.pen"))
        #expect(run.stdout.contains("woodcase help design"))
        #expect(run.stdout.contains("EXIT CODES"))
    }

    @Test("The top-level --help carries the same primer")
    func topLevelHelpIsThePrimer() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--help")
        #expect(run.status == 0)
        #expect(run.stdout.contains("woodcase help design"))
    }

    // MARK: - Topics

    @Test("`woodcase help` lists the topics, with no file and no arguments")
    func helpListsTopics() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help")
        #expect(run.status == 0)
        #expect(run.stdout.contains("design"))
        #expect(run.stdout.contains("woodcase help design"))
        for topic in HelpTopic.allCases {
            #expect(run.stdout.contains(topic.summary), "\(topic.rawValue) is missing from the list")
        }
    }

    /// The primer's budget: a page an agent reads once, not a manual.
    ///
    /// It was 60 lines until `--guard` joined `--rev` in it (leaf `2NW90`), then 70. The
    /// Quill run (`project/2026-09-01-quill-mobile-agents-dx.md`) raised it again, on the
    /// finding that agents are given no skill file and stop reading at this topic: what is
    /// not here is not known, and four agents rebuilt by hand what one paragraph on
    /// components would have given them. So the topic now carries components, values and
    /// reads too, and ends by naming the verb that owns each thing it left out.
    ///
    /// It is still a budget. A section that will not fit belongs in a verb's `--help`,
    /// pointed at from the see-also foot. Raised to 140 when `--dry-run` and
    /// `help codegen` each earned a line; raise it again deliberately, never silently.
    /// Raised to 145 for FONTS AND WIDTHS: a reader who does not know the cache is
    /// `$WOODCASE_HOME/fonts` cannot tell a fallback measurement from a real one, and
    /// the 2026-09-08 trial lost an hour to exactly that.
    /// Raised to 149 for the `--` separator: a dash-prefixed variable name is every name
    /// in a design-token file, and round two of the same trial had two agents blocked by
    /// it — one renamed its whole token set to get past it. Three lines and the see-also
    /// row that points at `vars set --help`, which carries the rest.
    /// Raised to 154 for two more from the same round: the `$` rule now says it holds on
    /// both routes and mid-string (two lines), and THE LOOP hands a repeated
    /// write-then-measure to `js` (three lines) — round two's control agent ran that loop
    /// as eleven transactions with the `js` paragraph in front of it, because nothing
    /// said *this* is the moment.
    private static let designTopicLineBudget = 154

    @Test("`woodcase help design` needs no file, and stays inside its budget")
    func designTopicFitsAScreen() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "design")
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        #expect(
            lines.count <= Self.designTopicLineBudget,
            "the design topic is \(lines.count) lines; the budget is \(Self.designTopicLineBudget)"
        )
        let widest = lines.map(\.count).max() ?? 0
        #expect(widest <= 100, "the design topic is \(widest) columns wide; one screen is 100")
    }

    @Test("The design topic teaches the rules every verb assumes")
    func designTopicTeachesTheRules() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "design")
        let expectations: [(String, String)] = [
            ("flex-first layout", "lays its children out horizontally"),
            ("only the root is placed", "is placed by coordinates"),
            ("naming", "cannot be addressed"),
            ("name-path addressing", "Dashboard/Header/Title"),
            ("instance addressing", "Orders/Value"),
            ("batch tags", "@hero"),
            ("ambiguity lists candidates", "listing every candidate"),
            ("the read-write-verify loop", "--rev"),
            ("verify with a read", "woodcase tree design.pen Card"),
        ]
        for (rule, evidence) in expectations {
            #expect(run.stdout.contains(evidence), "the design topic does not teach \(rule)")
        }
    }

    // MARK: - Verbs through help

    @Test("`woodcase help <verb>` still prints that verb's help")
    func helpForwardsToAVerb() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let viaHelp = try fixture.run("help", "tree")
        let viaFlag = try fixture.run("tree", "--help")
        #expect(viaHelp.status == 0)
        #expect(viaHelp.stdout == viaFlag.stdout)
    }

    @Test("`woodcase help <verb> <subverb>` walks into a group")
    func helpForwardsToANestedVerb() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "vars", "set")
        #expect(run.status == 0)
        #expect(run.stdout.contains("woodcase vars set"))
    }

    @Test("A subject that is neither a topic nor a verb is a usage error that says what is")
    func unknownSubjectIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "nonsense")
        #expect(run.status == 2)
        #expect(run.stderr.contains("nonsense"))
        #expect(run.stderr.contains("`woodcase help`"))
        #expect(run.stderr.contains("design"))
    }

    // MARK: - Every verb's own screen

    @Test("Every verb's abstract states its class")
    func abstractsStateTheClass() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--help")
        guard let start = run.stdoutLines.firstIndex(of: "SUBCOMMANDS:") else {
            Issue.record("--help printed no SUBCOMMANDS section")
            return
        }
        let rows = run.stdoutLines[start...]
        for verb in Self.classedVerbs {
            let row = rows.first { $0.hasPrefix("  \(verb) ") }
            let abstract = row?
                .trimmingCharacters(in: .whitespaces)
                .drop(while: { $0 != " " })
                .trimmingCharacters(in: .whitespaces) ?? ""
            #expect(
                ["Read:", "Write:", "Render:", "Read and write:"].contains { abstract.hasPrefix($0) },
                "\(verb)'s abstract does not say its class: \(abstract)"
            )
        }
    }

    @Test("Every verb's help carries a worked example")
    func everyVerbHasAWorkedExample() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        for verb in Self.verbsWithExamples {
            let run = try fixture.run(verb + ["--help"])
            // An example is an indented command line; prose about another verb is not,
            // because ArgumentParser wraps discussion paragraphs flush left.
            let example = run.stdoutLines.first {
                $0.hasPrefix("  ") && $0.contains("woodcase \(verb.joined(separator: " "))")
            }
            #expect(example != nil, "`woodcase \(verb.joined(separator: " "))` has no worked example")
        }
    }

    // MARK: - The codegen topic

    /// `woodcase help codegen` is the only place the CLI says how to build a component
    /// the React emitter recognizes, so it is held to the recipes topic's bar: every bare
    /// `  woodcase …` line in it is extracted and run, in order, against one scratch file.
    /// A line that is a *form* rather than a step — one carrying a placeholder, or a
    /// pointer at another verb — is written in backticks, which is what keeps it out of
    /// both the run and an agent's copy-paste.
    /// This topic's budget, deliberately above the design topic's 70.
    ///
    /// `help design` is a page of rules; this one is a primer for a subsystem — eight
    /// concepts and a worked example an agent pastes whole — and there is no honest way
    /// to teach a component's parameters, its states and its instances in seventy lines.
    /// It is still a budget: a section that will not fit belongs in `generate react
    /// --help` or in a lint message, not here. Raised from 120 to 136 for the SwiftUI
    /// target's section — the package, its fonts, and the four commands that build, open,
    /// snapshot and check it — which no other topic or verb help puts in one place.
    private static let codegenTopicLineBudget = 136

    @Test("`woodcase help codegen` needs no file, and fits one screen's width")
    func codegenTopicPrints() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "codegen")
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(!run.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let lines = run.stdoutLines
        #expect(
            lines.count <= Self.codegenTopicLineBudget,
            "the codegen topic is \(lines.count) lines; the budget is \(Self.codegenTopicLineBudget)"
        )
        let widest = lines.map(\.count).max() ?? 0
        #expect(widest <= 100, "the codegen topic is \(widest) columns wide; one screen is 100")
    }

    /// Every role, from the enum rather than a list written twice: a role the analyzer
    /// accepts and the topic does not name is a component an agent cannot be told to build.
    @Test("The codegen topic names every role the analyzer accepts")
    func codegenTopicNamesEveryRole() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "codegen")
        for role in ComponentRole.allCases {
            #expect(
                run.stdout.contains(role.rawValue),
                "the codegen topic does not name the \(role.rawValue) role"
            )
        }
    }

    @Test("The codegen topic teaches every key the emitter reads, and where it is checked")
    func codegenTopicTeachesTheKeys() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "codegen")
        let expectations: [(String, String)] = [
            ("what marks a component", "common.reusable=true"),
            ("what becomes a page", "pages/"),
            ("_role, with its deep-key write", "common.metadata._role=button"),
            ("_props, with its deep-key write", "common.metadata._props.label=Label"),
            ("_action, with its deep-key write", "common.metadata._action="),
            ("_states, with its deep-key write", "common.metadata._states."),
            ("that _bind exists and is not read", "_bind"),
            ("removing one key without the rest", "=null"),
            ("the state-variant naming convention", "{state}"),
            ("reading the parameters back", "woodcase get design.pen Button"),
            ("that an uncovered override inlines", "Customized from"),
            ("the neighboring topic", "help design"),
            ("the verb's own flags", "generate react --help"),
            ("where these become a report", "codegen-unmapped-override"),
        ]
        for (rule, evidence) in expectations {
            #expect(run.stdout.contains(evidence), "the codegen topic does not teach \(rule)")
        }
    }

    /// Both targets read the same components, so one topic teaches both; the SwiftUI half
    /// is what the package is and how to build, run and check it.
    @Test("The codegen topic teaches the SwiftUI target: what it writes and how to build and run it")
    func codegenTopicTeachesSwiftUI() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "codegen")
        let expectations: [(String, String)] = [
            ("the verb", "woodcase generate swiftui"),
            ("where the fonts and images go", "Resources"),
            ("building the package", "swift build"),
            ("opening the catalog", "swift run <Name>Catalog"),
            ("rendering the catalog", "--snapshot"),
            ("checking the fonts registered", "--fonts"),
            ("registering fonts for an app's own views", "PenFonts.register()"),
            ("the verb's own flags", "generate swiftui --help"),
        ]
        for (rule, evidence) in expectations {
            #expect(run.stdout.contains(evidence), "the codegen topic does not teach \(rule)")
        }
    }

    @Test("Every command in the codegen topic exits 0, in order, against one file")
    func everyCodegenCommandExitsZero() throws {
        let commands = RecipesTests.extractCommands(from: HelpTopic.codegen.body)
        #expect(commands.count >= 8, "the codegen topic's worked example is \(commands.count) commands")

        let fixture = try CommandFixture(fixture: "batch.pen")
        for (index, command) in commands.enumerated() {
            let run = try fixture.run(command.arguments, stdin: command.stdin)
            #expect(
                run.status == 0,
                """
                codegen command \(index) `woodcase \(command.arguments.joined(separator: " "))` \
                exited \(run.status): \(run.stderr)
                """
            )
        }
    }

    /// The example is only worth pasting if it ends in the thing it promises: a component
    /// with a typed props interface, and an instance that reaches it as attributes.
    @Test("The codegen topic's worked example emits a typed props interface")
    func codegenWorkedExampleEmitsProps() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        for command in RecipesTests.extractCommands(from: HelpTopic.codegen.body) {
            _ = try fixture.run(command.arguments, stdin: command.stdin)
        }
        let button = fixture.root
            .appendingPathComponent("ui/components/Button.tsx")
        let page = fixture.root.appendingPathComponent("ui/pages/Home.tsx")
        let buttonSource = try String(contentsOf: button, encoding: .utf8)
        let pageSource = try String(contentsOf: page, encoding: .utf8)
        #expect(buttonSource.contains("interface ButtonProps {"))
        #expect(buttonSource.contains("label?: string;"))
        #expect(buttonSource.contains("tint?: string;"))
        #expect(pageSource.contains("<Button label=\"Send\" tint=\"#FFD166\" />"))
    }

    /// Every verb over a document. `help` is excluded because it is not one.
    private static let classedVerbs = [
        "tree", "find", "get", "shot", "lint", "schema", "undo", "add", "set", "cp", "mv", "rm",
        "override", "apply", "js", "vars", "imports", "render", "themes", "generate", "migrate",
        "activity",
    ]

    /// Every verb that acts, as its command path. Groups (`vars`, `generate`) route to a
    /// subcommand rather than doing anything, so the example lives on the subcommand.
    private static let verbsWithExamples: [[String]] = [
        ["tree"], ["find"], ["get"], ["shot"], ["lint"], ["schema"], ["undo"], ["add"], ["set"], ["cp"],
        ["mv"], ["rm"],
        ["override"], ["apply"], ["js"], ["render"], ["themes"], ["migrate"], ["activity"],
        ["vars", "list"], ["vars", "set"], ["vars", "rm"], ["vars", "axis", "add"],
        ["imports", "list"], ["imports", "set"], ["imports", "rm"],
        ["generate", "react"],
    ]
}
