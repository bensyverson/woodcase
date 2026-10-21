//
//  CodegenPathCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The code-generation keys on the command line (leaf tRzkPS): `set` writes `codegen.role`
/// into `metadata.woodcase.role`, a write at the storage path is refused naming
/// `codegen.role`, and `woodcase help` spells only `codegen.*`.
@Suite("woodcase codegen paths")
struct CodegenPathCommandTests {
    @Test("set codegen.role=button stores the role where ComponentAnalyzer reads it")
    func setRole() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let run = try fixture.run("set", fixture.file.path, "StatCard", "codegen.role=button", "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        let document = try PenParser.parse(contentsOf: fixture.file)
        let component = ComponentAnalyzer.analyze(document).first { $0.name == "StatCard" }
        #expect(component?.role == .button)
        #expect(try PenFileProbe(fixture.file).node("StatCard")?.common.metadata?[woodcase: .role] == "button")
    }

    @Test("A write to common.metadata.woodcase.role is refused, naming codegen.role")
    func rawRoleRefused() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let run = try fixture.run("set", fixture.file.path, "StatCard", "common.metadata.woodcase.role=button")
        #expect(run.status != 0)
        #expect(run.stderr.contains("common.metadata.woodcase.role is stored for you; write codegen.role"), "\(run.stderr)")
        #expect(try PenFileProbe(fixture.file).node("StatCard")?.common.metadata?[woodcase: .role] == nil)
    }

    @Test("woodcase help spells the code-generation keys only as codegen.*")
    func helpSpellsCodegen() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        for topic in [["help", "codegen"], ["help", "design"], ["help", "set"], ["help", "lint"], ["help", "generate"]] {
            let run = try fixture.run(topic)
            #expect(run.status == 0, "\(topic): \(run.stderr)")
            for key in ["props", "role", "states", "action", "scroll"] {
                #expect(!run.stdout.contains("metadata.woodcase.\(key)"), "`\(topic.joined(separator: " "))` spells \(key) raw")
                #expect(!run.stdout.contains("woodcase.\(key)"), "`\(topic.joined(separator: " "))` spells woodcase.\(key)")
            }
        }
        let codegen = try fixture.run("help", "codegen")
        #expect(codegen.stdout.contains("codegen.role=button"), "\(codegen.stdout)")
        #expect(codegen.stdout.contains("codegen.props.label="), "\(codegen.stdout)")
    }
}
