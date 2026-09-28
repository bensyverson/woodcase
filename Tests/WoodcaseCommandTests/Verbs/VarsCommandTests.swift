//
//  VarsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

struct VarsCommandTests {
    // MARK: - Helpers

    /// The `.pen` file's JSON, as written back to disk.
    ///
    /// Non-throwing so it can sit inside `#require`, which cannot expand a throwing call.
    private func document(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// One variable's raw JSON from a written `.pen` file.
    private func variable(_ name: String, in url: URL) -> [String: Any]? {
        (document(url)["variables"] as? [String: Any])?[name] as? [String: Any]
    }

    /// The decoded `--json` object a run printed.
    private func json(_ run: CommandRun) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(run.stdout.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: - Listing

    @Test("A bare `vars <file>` lists each variable's name, type, reference count and value")
    func listsSimpleVariables() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout == """
        variables
          headline      string   1 ref   Breaking News
          primaryColor  color    1 ref   #FF6600
          showSubtitle  boolean  0 refs  true
          spacing       number   0 refs  16

        """)
    }

    @Test("A themed variable shows one indented row per variant, and the axes follow")
    func listsThemedVariablesAndAxes() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run("vars", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout.contains("  bgColor   color   1 ref\n"))
        #expect(run.stdout.contains("    mode=light  #FFFFFF\n"))
        #expect(run.stdout.contains("    mode=dark   #1A1A1A\n"))
        #expect(run.stdout.contains("    *"))
        #expect(run.stdout.contains("#F0F0F0"))
        #expect(run.stdout.contains("axes\n"))
        #expect(run.stdout.contains("  density  compact, regular\n"))
        #expect(run.stdout.contains("  mode     light, dark\n"))
    }

    @Test("`--json` carries the variants, the axes and the document revision")
    func listsAsJSON() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run("vars", fixture.file.path, "--json")
        #expect(run.status == 0)
        let object = json(run)
        #expect(object["revision"] is String)
        let variables = try #require(object["variables"] as? [[String: Any]])
        let bgColor = try #require(variables.first { $0["name"] as? String == "bgColor" })
        #expect(bgColor["type"] as? String == "color")
        let references = try #require(bgColor["references"] as? [String: Any])
        #expect(references["nodes"] as? Int == 1)
        let values = try #require(bgColor["values"] as? [[String: Any]])
        #expect(values.count == 3)
        #expect(values[0]["theme"] as? [String: String] == ["mode": "light"])
        #expect(values[2]["theme"] as? [String: String] == nil)
        let axes = try #require(object["axes"] as? [[String: Any]])
        #expect(axes.map { $0["name"] as? String } == ["density", "mode"])
    }

    @Test("A document with neither variables nor axes says so and exits 0")
    func listsNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("vars", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout == "No variables or theme axes in batch.pen.\n")
    }

    @Test("A missing file is a target failure")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", fixture.root.appendingPathComponent("nope.pen").path)
        #expect(run.status == 4)
        #expect(run.stderr.contains("no such file"))
    }

    // MARK: - set

    @Test("Setting a new name adds the variable, typed by its value, and prints the revision")
    func setAddsVariable() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "brand=#123456", "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdout.contains("brand  color  0 refs  #123456"))
        #expect(run.stdout.contains("revision "))
        let stored = try #require(variable("brand", in: fixture.file))
        #expect(stored["type"] as? String == "color")
        #expect(stored["value"] as? String == "#123456")
    }

    @Test("Setting an existing name updates it in place")
    func setUpdatesVariable() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "spacing=24", "--as", "ana")
        #expect(run.status == 0)
        let stored = try #require(variable("spacing", in: fixture.file))
        #expect(stored["value"] as? Int == 24)
        #expect(stored["type"] as? String == "number")
    }

    @Test("An existing variable's declared type wins over the new value's inferred type")
    func setKeepsDeclaredType() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "headline=16", "--as", "ana")
        #expect(run.status == 0)
        let stored = try #require(variable("headline", in: fixture.file))
        #expect(stored["type"] as? String == "string")
        #expect(stored["value"] as? String == "16")
    }

    @Test("A value the declared type cannot hold is a usage error naming both")
    func setRefusesMismatchedValue() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "spacing=wide", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("spacing"))
        #expect(run.stderr.contains("number"))
        #expect(run.stderr.contains("--type"))
        let stored = try #require(variable("spacing", in: fixture.file))
        #expect(stored["value"] as? Int == 16)
    }

    @Test("`--type` declares the type when the value would have inferred another")
    func setHonoursExplicitType() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "label=16", "--type", "string", "--as", "ana"
        )
        #expect(run.status == 0)
        let stored = try #require(variable("label", in: fixture.file))
        #expect(stored["type"] as? String == "string")
        #expect(stored["value"] as? String == "16")
    }

    /// Criterion P6g.
    @Test("Setting a themed value on a fresh axis creates the axis and keeps both values")
    func setOnFreshAxisCreatesAxisAndBothValues() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "primaryColor=#00FF00",
            "--theme", "mode=dark", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("axis mode: dark"))

        let themes = try #require(document(fixture.file)["themes"] as? [String: [String]])
        #expect(themes == ["mode": ["dark"]])

        let stored = try #require(variable("primaryColor", in: fixture.file))
        let values = try #require(stored["value"] as? [[String: Any]])
        #expect(values.count == 2)
        #expect(values[0]["value"] as? String == "#FF6600")
        #expect(values[0]["theme"] as? [String: String] == nil)
        #expect(values[1]["value"] as? String == "#00FF00")
        #expect(values[1]["theme"] as? [String: String] == ["mode": "dark"])

        #expect(run.stdout.contains("#FF6600"))
        #expect(run.stdout.contains("mode=dark  #00FF00"))
    }

    @Test("A second themed value registers the new option on the axis that exists")
    func setRegistersNewOptionOnExistingAxis() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "bgColor=#222222",
            "--theme", "mode=dim", "--as", "ana"
        )
        #expect(run.status == 0)
        let themes = try #require(document(fixture.file)["themes"] as? [String: [String]])
        #expect(themes["mode"] == ["light", "dark", "dim"])
        let values = try #require(variable("bgColor", in: fixture.file)?["value"] as? [[String: Any]])
        #expect(values.count == 4)
    }

    @Test("Setting the same pin twice replaces that variant rather than appending")
    func setReplacesMatchingVariant() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "bgColor=#222222",
            "--theme", "mode=dark", "--as", "ana"
        )
        #expect(run.status == 0)
        let values = try #require(variable("bgColor", in: fixture.file)?["value"] as? [[String: Any]])
        #expect(values.count == 3)
        #expect(values[1]["value"] as? String == "#222222")
    }

    @Test("Without a pin, a themed variable's default variant is the one that changes")
    func setUpdatesDefaultVariant() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "bgColor=#EEEEEE", "--as", "ana")
        #expect(run.status == 0)
        let values = try #require(variable("bgColor", in: fixture.file)?["value"] as? [[String: Any]])
        #expect(values.count == 3)
        #expect(values[2]["value"] as? String == "#EEEEEE")
        #expect(values[0]["value"] as? String == "#FFFFFF")
    }

    @Test("A write is logged as a `var` event")
    func setLogsAnEvent() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        _ = try fixture.run("vars", "set", fixture.file.path, "brand=#123456", "--as", "ana")
        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        #expect(log.contains("\"op\":\"var\""))
        #expect(log.contains("ana"))
    }

    @Test("Registering an axis is logged as a `theme` event beside the `var` one")
    func setLogsAxisEvent() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        _ = try fixture.run(
            "vars", "set", fixture.file.path, "primaryColor=#00FF00",
            "--theme", "mode=dark", "--as", "ana"
        )
        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        #expect(log.contains("\"op\":\"theme\""))
        #expect(log.contains("\"op\":\"var\""))
    }

    @Test("A malformed theme pin is a usage error")
    func setRefusesMalformedPin() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "set", fixture.file.path, "brand=#123456", "--theme", "dark", "--as", "ana"
        )
        #expect(run.status == 2)
        #expect(run.stderr.contains("axis=value"))
    }

    // MARK: - rm

    /// Criterion AZw.
    @Test("Removing a referenced variable fails naming the referencing nodes")
    func removeRefusesWhileReferenced() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "rm", fixture.file.path, "primaryColor", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("primaryColor"))
        #expect(run.stderr.contains("1 node"))
        #expect(run.stderr.contains("#text1"))
        #expect(run.stderr.contains("--force"))
        #expect(variable("primaryColor", in: fixture.file) != nil)
    }

    @Test("`--force` removes a referenced variable anyway")
    func removeForced() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "rm", fixture.file.path, "primaryColor", "--force", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("primaryColor"))
        #expect(run.stdout.contains("revision "))
        #expect(variable("primaryColor", in: fixture.file) == nil)
    }

    @Test("An unreferenced variable is removed without a flag")
    func removeUnreferenced() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "rm", fixture.file.path, "spacing", "--as", "ana")
        #expect(run.status == 0)
        #expect(variable("spacing", in: fixture.file) == nil)
    }

    @Test("A variable referenced only by another variable is named in the refusal too")
    func removeNamesReferencingVariables() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        _ = try fixture.run(
            "vars", "set", fixture.file.path, "border=$primaryColor", "--type", "color", "--as", "ana"
        )
        let run = try fixture.run("vars", "rm", fixture.file.path, "primaryColor", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("border"))
    }

    @Test("Removing a variable the document does not define is a usage error naming it")
    func removeUnknownVariable() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "rm", fixture.file.path, "nope", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("nope"))
    }

    // MARK: - axis add

    @Test("`axis add` creates an axis with the options named")
    func axisAddCreates() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run(
            "vars", "axis", "add", fixture.file.path, "mode=light,dark", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("mode  light, dark"))
        #expect(run.stdout.contains("revision "))
        let themes = try #require(document(fixture.file)["themes"] as? [String: [String]])
        #expect(themes == ["mode": ["light", "dark"]])
    }

    @Test("`axis add` appends options to an axis that already exists, keeping the order")
    func axisAddAppends() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let run = try fixture.run(
            "vars", "axis", "add", fixture.file.path, "mode=dark,hc", "--as", "ana"
        )
        #expect(run.status == 0)
        let themes = try #require(document(fixture.file)["themes"] as? [String: [String]])
        #expect(themes["mode"] == ["light", "dark", "hc"])
    }

    @Test("`axis add` with options the axis already has says so and writes nothing")
    func axisAddIsNotSilentlyANoOp() throws {
        let fixture = try CommandFixture(fixture: "parser-themed-variables.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let run = try fixture.run(
            "vars", "axis", "add", fixture.file.path, "mode=light,dark", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("already"))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    @Test("`axis add` with a malformed argument is a usage error")
    func axisAddRefusesMalformed() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "axis", "add", fixture.file.path, "mode", "--as", "ana")
        #expect(run.status == 2)
    }
}
