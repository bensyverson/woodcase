//
//  WoodcaseHomeTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The one rule that answers "where does Woodcase keep a user's state?".
///
/// The activity log's `$WOODCASE_HOME` override and the font and image caches are the
/// same question asked three times, so they resolve through one enum. A second resolver
/// would drift the moment someone changed the default.
@Suite("Where a user's Woodcase directory is")
struct WoodcaseHomeTests {
    @Test("A set variable is the whole answer")
    func overrideWins() {
        let environment = [WoodcaseHome.environmentVariable: "/var/state/woodcase"]

        #expect(WoodcaseHome.override(in: environment)?.path == "/var/state/woodcase")
        #expect(WoodcaseHome.directory(in: environment).path == "/var/state/woodcase")
    }

    @Test("An empty variable is not an override")
    func emptyIsIgnored() {
        let environment = [WoodcaseHome.environmentVariable: ""]

        #expect(WoodcaseHome.override(in: environment) == nil)
        #expect(WoodcaseHome.directory(in: environment).lastPathComponent == WoodcaseHome.directoryName)
    }

    @Test("With nothing set the directory is .woodcase in the user's home")
    func defaultsToDotWoodcase() {
        let directory = WoodcaseHome.directory(in: [:])

        #expect(WoodcaseHome.override(in: [:]) == nil)
        #expect(directory.path == NSHomeDirectory() + "/" + WoodcaseHome.directoryName)
    }

    @Test("The activity log reads the same variable and the same directory name")
    func theLogSharesTheRule() {
        #expect(ActivityLog.homeEnvironmentVariable == WoodcaseHome.environmentVariable)
        #expect(ActivityLog.directoryName == WoodcaseHome.directoryName)
    }
}
