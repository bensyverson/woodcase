//
//  JsDeclarationTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore
import WoodcaseScripting

/// The `.d.ts` in `woodcase help js`, held to the prelude that actually defines `doc`.
///
/// A declaration that has drifted from the runtime is worse than none: it teaches a call
/// that throws, and an agent has no way to tell which of the two is wrong. So the
/// declaration is checked against ``WoodcaseScripting/ScriptHost/members()`` — the member
/// table read back out of the running prelude — in both directions, and the keys the
/// prelude retired are checked to be absent.
///
/// It lives beside the topic rather than in `WoodcaseScriptingTests` because the two
/// halves live in different targets: the text is `WoodcaseCommandCore`'s and the runtime
/// is `WoodcaseScripting`'s, and this is the only test target that imports both.
@Suite("`help js` declares what the prelude defines")
struct JsDeclarationTests {
    /// The declaration, parsed out of the topic once.
    private let declared = Declaration(topic: HelpTopic.js.body)

    // MARK: - Both directions

    @Test("Every member the prelude defines is declared, and nothing else is")
    func theMembersMatch() {
        let runtime = ScriptHost.members()
            .filter { $0.kind != .namespace }
            .map(\.name)
        #expect(declared.members.keys.sorted() == runtime.sorted())
    }

    @Test("Every option key the prelude takes is declared, and nothing else is")
    func theOptionKeysMatch() {
        for member in ScriptHost.members() where member.kind == .call {
            let keys = declared.members[member.name]
            let declaredKeys = keys?.sorted().description ?? "no such member"
            #expect(
                keys?.sorted() == member.options.sorted(),
                "doc.\(member.name) takes \(member.options.sorted()) and the .d.ts declares \(declaredKeys)"
            )
        }
    }

    @Test("The namespaces are declared as objects, not as calls")
    func theNamespacesAreObjects() {
        for namespace in ScriptHost.members() where namespace.kind == .namespace {
            #expect(
                declared.namespaces.contains(namespace.name),
                "doc.\(namespace.name) is a namespace and the .d.ts does not declare one"
            )
        }
    }

    /// The CLI flags the prelude answers with a redirecting sentence rather than an
    /// option. Declaring one would teach a call the prelude refuses on purpose, so each
    /// has to be absent — the reason `retired` exists in the member table at all.
    @Test("No key the prelude retired is declared as an option")
    func theRetiredKeysAreNotDeclared() {
        let retired: [(member: String, key: String)] = [
            ("tree", "absolute"), ("get", "instances"), ("lint", "summary"), ("lint", "list"),
            ("add", "tag"), ("cp", "tag"), ("cp", "name"), ("cp", "times"),
        ]
        for (member, key) in retired {
            #expect(
                declared.members[member]?.contains(key) != true,
                "the .d.ts declares doc.\(member)'s retired \(key) option"
            )
        }
    }

    // MARK: - The parser

    /// What the topic's `declare const doc` block says `doc` has.
    ///
    /// A small parser rather than a second copy of the table: the point of the suite is
    /// that the shipped text and the running prelude agree, which a list written here
    /// would not prove. It reads the shape this topic is written in — one member per
    /// declaration, options as a named `interface` — and nothing more general.
    struct Declaration {
        /// Reads the declaration out of a topic body.
        ///
        /// - Parameter topic: The topic body, verbatim.
        init(topic: String) {
            let lines = topic.components(separatedBy: "\n")
            let options = Self.optionInterfaces(in: lines)
            var members: [String: [String]] = [:]
            var namespaces: Set<String> = []
            var namespace: String?
            var buffer = ""

            for line in JsTopicText.blockBody(in: lines, openedBy: JsTopicText.docOpener) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.isEmpty || text.hasPrefix("/*") || text.hasPrefix("*") { continue }
                if let opened = text.firstMatch(of: /^(?<name>\w+): \{$/) {
                    namespace = String(opened.output.name)
                    namespaces.insert(String(opened.output.name))
                    continue
                }
                if text == "};" || text == "}" {
                    namespace = nil
                    continue
                }
                buffer += buffer.isEmpty ? text : " " + text
                guard buffer.hasSuffix(";") else { continue }
                defer { buffer = "" }
                guard let member = buffer.firstMatch(of: /^(?:readonly )?(?<name>\w+)[(:]/) else {
                    continue
                }
                let name = namespace.map { "\($0).\(member.output.name)" }
                    ?? String(member.output.name)
                let interface = buffer.firstMatch(of: /options\?: (?<type>\w+)/)?.output.type
                members[name] = interface.flatMap { options[String($0)] } ?? []
            }
            self.members = members
            self.namespaces = namespaces
        }

        /// Every declared member of `doc`, dotted inside a namespace, to the option keys
        /// its own options interface declares.
        let members: [String: [String]]

        /// Every namespace `doc` declares as an object of its own.
        let namespaces: Set<String>

        /// Every `interface … { key?: …; … }` line in the topic, as its option keys.
        private static func optionInterfaces(in lines: [String]) -> [String: [String]] {
            var interfaces: [String: [String]] = [:]
            for line in lines {
                guard let match = line.firstMatch(
                    of: /^\s*interface (?<name>\w+Options) \{(?<body>[^}]*)\}/
                ) else { continue }
                interfaces[String(match.output.name)] = String(match.output.body)
                    .matches(of: /(?<key>\w+)\?:/)
                    .map { String($0.output.key) }
            }
            return interfaces
        }
    }
}
