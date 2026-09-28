//
//  VarsSetPairsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `vars set` with more than one `name=value` on the line.
///
/// A token layer is written all at once or not at all, and one process launch per
/// colour is the shape that made it 34 launches. Several pairs go through one
/// transaction, one `var` event each, so `activity` and `undo` still read as they did.
@Suite("`vars set` with several pairs")
struct VarsSetPairsTests {
    /// Criterion e0b.
    @Test("Two pairs are written in one call, in one transaction")
    func twoPairsAreWrittenTogether() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "a=1", "b=2", "--as", "ana"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("a"))
        #expect(run.stdout.contains("b"))

        let data = try Data(contentsOf: fixture.file)
        let object = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        #expect((variables["a"] as? [String: Any])?["value"] as? Int == 1)
        #expect((variables["b"] as? [String: Any])?["value"] as? Int == 2)
        #expect(run.stdoutLines.count(where: { $0.hasPrefix("revision ") }) == 1, "more than one revision")
    }

    @Test("Each variable is one `var` event, and the two share one transaction")
    func eachVariableIsItsOwnEventInOneTransaction() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        #expect(try fixture.run("vars", "set", fixture.file.path, "a=1", "b=2", "--as", "ana").status == 0)
        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        let lines = log.split(separator: "\n").filter { $0.contains("\"op\":\"var\"") }
        #expect(lines.count == 2, "expected one var event per variable, got \(lines.count)")
        let batches = Set(lines.map { line -> String in
            let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            return object?["batch"] as? String ?? ""
        })
        #expect(batches.count == 1, "the two events did not share one transaction: \(batches)")
    }

    @Test("One undo takes back the whole call")
    func oneUndoTakesBackBothPairs() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        #expect(try fixture.run("vars", "set", fixture.file.path, "a=1", "b=2", "--as", "ana").status == 0)
        #expect(try fixture.run("undo", fixture.file.path, "--as", "ana").status == 0)
        let data = try Data(contentsOf: fixture.file)
        let object = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        let variables = (object["variables"] as? [String: Any]) ?? [:]
        #expect(variables["a"] == nil, "undo left the first pair behind")
        #expect(variables["b"] == nil, "undo left the second pair behind")
    }

    @Test("--theme and --type apply to every pair")
    func themeAndTypeApplyToEveryPair() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "one=10", "two=20",
            "--type", "string", "--theme", "mode=dark", "--as", "ana"
        )
        #expect(run.status == 0, "\(run.stderr)")
        let data = try Data(contentsOf: fixture.file)
        let object = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        for name in ["one", "two"] {
            let stored = try #require(variables[name] as? [String: Any])
            #expect(stored["type"] as? String == "string", "\(name) did not take --type")
            let values = try #require(stored["value"] as? [[String: Any]])
            #expect(values.last?["theme"] as? [String: String] == ["mode": "dark"], "\(name) did not take --theme")
        }
        #expect(object["themes"] as? [String: [String]] == ["mode": ["dark"]])
        #expect(run.stdout.contains("axis mode: dark"), "the axis was registered once but not reported")
    }

    @Test("A pair that fails its type takes the whole call with it")
    func aFailingPairRollsBackTheCall() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "good=#112233", "spacing=wide", "--as", "ana"
        )
        #expect(run.status == 2)
        let data = try Data(contentsOf: fixture.file)
        let object = try #require((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        #expect(variables["good"] == nil, "a failed call left the earlier pair written")
    }

    @Test("`vars set --help` says --theme and --type apply to every pair")
    func helpSaysTheOptionsApplyToEveryPair() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", "--help")
        #expect(run.status == 0)
        #expect(
            run.stdout.contains("every pair"),
            "`vars set --help` does not say --theme and --type apply to every pair"
        )
    }
}
