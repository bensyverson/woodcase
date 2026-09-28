//
//  VarsSetExistingTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// What `vars set` says when the name it was given already exists.
///
/// `vars set` is add-or-change and printed the same outline either way, so a request to
/// "add" a token that was already there silently recoloured every reference. One line
/// before the outline names what was displaced and how much of the document was looking
/// at it; a fresh name gets nothing extra, because there is nothing to say.
@Suite("`vars set` over a name that already exists")
struct VarsSetExistingTests {
    /// Criterion yDh.
    @Test("An existing name is announced with its old value and its reference count")
    func existingNameNamesTheOldValueAndCount() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "primaryColor=#00FF00", "--as", "ana")
        #expect(run.status == 0)
        #expect(
            run.stdout.contains("#FF6600"),
            "the old value is not named: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("1 ref"),
            "the reference count is not named: \(run.stdout)"
        )
        #expect(run.stdout.contains("primaryColor  color  1 ref  #00FF00"), "the outline is missing")
    }

    @Test("A fresh name prints nothing extra")
    func freshNameSaysNothingExtra() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "brand=#123456", "--as", "ana")
        #expect(run.status == 0)
        #expect(!run.stdout.contains("already"), "a fresh variable was announced as existing: \(run.stdout)")
        #expect(run.stdoutLines.first == "  brand  color  0 refs  #123456", "the outline did not lead")
    }

    @Test("A themed old value shows every option's value")
    func themedOldValueShowsEveryOption() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "bgColor=#222222", "--as", "ana")
        #expect(run.status == 0)
        let announced = try #require(run.stdoutLines.first)
        #expect(announced.contains("#FFFFFF"), "the light option's old value is missing: \(announced)")
        #expect(announced.contains("#1A1A1A"), "the dark option's old value is missing: \(announced)")
        #expect(announced.contains("#F0F0F0"), "the default option's old value is missing: \(announced)")
    }

    @Test("--json carries the previous state as a field, not as a sentence")
    func jsonCarriesPreviousAsAField() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "primaryColor=#00FF00", "--as", "ana", "--json"
        )
        #expect(run.status == 0)
        let object = try #require(
            (try? JSONSerialization.jsonObject(with: Data(run.stdout.utf8))) as? [String: Any]
        )
        let previous = try #require(object["previous"] as? [[String: Any]], "no previous field: \(run.stdout)")
        #expect(previous.count == 1)
        #expect(previous[0]["name"] as? String == "primaryColor")
        let references = try #require(previous[0]["references"] as? [String: Any])
        #expect(references["nodes"] as? Int == 1)
        let values = try #require(previous[0]["values"] as? [[String: Any]])
        #expect(values[0]["value"] as? String == "#FF6600")
    }

    @Test("--json for a fresh name carries no previous field")
    func jsonForAFreshNameHasNoPreviousField() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "brand=#123456", "--as", "ana", "--json")
        #expect(run.status == 0)
        let object = try #require(
            (try? JSONSerialization.jsonObject(with: Data(run.stdout.utf8))) as? [String: Any]
        )
        #expect(object["previous"] == nil, "a fresh variable carried a previous field: \(run.stdout)")
    }
}
