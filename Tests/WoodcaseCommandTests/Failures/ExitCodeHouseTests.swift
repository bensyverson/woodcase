//
//  ExitCodeHouseTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Testing
@testable import WoodcaseCommandCore

/// Pins the house exit-code table. An agent learns these numbers once, across every
/// tool in the family, so they are a contract rather than an implementation detail.
@Suite("House exit codes")
struct ExitCodeHouseTests {
    @Test("The table has the six documented codes")
    func tableValues() {
        #expect(ExitCode.success.rawValue == 0)
        #expect(ExitCode.cleanNegative.rawValue == 1)
        #expect(ExitCode.usage.rawValue == 2)
        #expect(ExitCode.conflict.rawValue == 3)
        #expect(ExitCode.targetFailure.rawValue == 4)
        #expect(ExitCode.environment.rawValue == 5)
    }

    @Test("Clean negative is ArgumentParser's own plain failure")
    func cleanNegativeIsFailure() {
        #expect(ExitCode.cleanNegative == ExitCode.failure)
    }

    @Test("Usage is not ArgumentParser's default validation exit of 64")
    func usageOverridesArgumentParser() {
        #expect(ExitCode.usage != ExitCode.validationFailure)
        #expect(ExitCode.validationFailure.rawValue == 64)
    }
}
