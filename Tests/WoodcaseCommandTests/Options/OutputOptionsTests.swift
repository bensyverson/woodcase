//
//  OutputOptionsTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Testing
@testable import WoodcaseCommandCore

/// `--json` is always one flag away from any output.
@Suite("--json output")
struct OutputOptionsTests {
    @Test("The outline is the default")
    func defaultsToText() throws {
        #expect(try OutputOptions.parse([]).json == false)
    }

    @Test("--json asks for the machine shape")
    func jsonFlag() throws {
        #expect(try OutputOptions.parse(["--json"]).json)
    }
}
