//
//  IdentityOptionsTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Testing
@testable import WoodcaseCommandCore

/// `--as <name>`, defaulting from `$WOODCASE_AS`, is how every write is attributed.
@Suite("--as identity")
struct IdentityOptionsTests {
    /// The role every editing verb carries; the resolution logic is shared by all three.
    private typealias Attributed = IdentityOptions<Identity.Attribution>

    @Test("--as names the writer")
    func parsesTheFlag() throws {
        let options = try Attributed.parse(["--as", "ana"])
        #expect(options.identityName == "ana")
        #expect(options.identity(in: [:]) == "ana")
    }

    @Test("Neither the flag nor the variable leaves the edit unattributed")
    func noIdentityIsNil() throws {
        let options = try Attributed.parse([])
        #expect(options.identityName == nil)
        #expect(options.identity(in: [:]) == nil)
    }

    @Test("$WOODCASE_AS is the default")
    func environmentSuppliesTheDefault() throws {
        let options = try Attributed.parse([])
        #expect(options.identity(in: ["WOODCASE_AS": "ben"]) == "ben")
    }

    @Test("The flag beats the environment")
    func flagWinsOverEnvironment() throws {
        let options = try Attributed.parse(["--as", "ana"])
        #expect(options.identity(in: ["WOODCASE_AS": "ben"]) == "ana")
    }

    @Test("A blank name is not a name")
    func blankIsUnset() throws {
        #expect(try Attributed.parse(["--as", "   "]).identity(in: [:]) == nil)
        #expect(try Attributed.parse([]).identity(in: ["WOODCASE_AS": ""]) == nil)
        #expect(
            try Attributed.parse(["--as", " "]).identity(in: ["WOODCASE_AS": "ben"]) == "ben"
        )
    }

    @Test("Surrounding whitespace is trimmed off a name")
    func namesAreTrimmed() throws {
        #expect(try Attributed.parse(["--as", " ana "]).identity(in: [:]) == "ana")
    }

    @Test("The variable this group reads is named once")
    func environmentVariableName() {
        #expect(Identity.environmentVariable == "WOODCASE_AS")
    }

    @Test("Each role says something different about what --as does")
    func rolesSwapTheHelpText() {
        let attribution = Identity.Attribution.help.abstract
        let filter = Identity.Filter.help.abstract
        let required = Identity.Required.help.abstract
        #expect(attribution.contains("attribute"))
        #expect(attribution.contains("unattributed"))
        #expect(filter.contains("Show only this writer's events"))
        #expect(required.contains("refuses without one"))
        #expect(Set([attribution, filter, required]).count == 3)
        for text in [attribution, filter, required] {
            #expect(text.contains("$\(Identity.environmentVariable)"))
        }
    }
}
