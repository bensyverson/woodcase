//
//  PropertyAssignmentTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Pins the `key=value` value rules, because they are the one place the command line
/// guesses a type — and a wrong guess writes a plausible wrong value into the file.
@Suite("Parsing key=value on the command line")
struct PropertyAssignmentTests {
    // MARK: - Numbers

    @Test("A whole number is a number, not a string")
    func wholeNumber() throws {
        #expect(try PropertyAssignment.parse("kind.width=240").value == .int(240))
        #expect(try PropertyAssignment.parse("kind.x=-12").value == .int(-12))
    }

    @Test("A decimal is a number")
    func decimal() throws {
        #expect(try PropertyAssignment.parse("common.opacity=0.5").value == .double(0.5))
        #expect(try PropertyAssignment.parse("common.rotation=-1.25").value == .double(-1.25))
    }

    @Test("Words that Double() would accept are still words")
    func notQuiteNumbers() throws {
        #expect(try PropertyAssignment.parse("common.name=nan").value == .string("nan"))
        #expect(try PropertyAssignment.parse("common.name=infinity").value == .string("infinity"))
    }

    // MARK: - Literals

    @Test("true, false and null are themselves")
    func literals() throws {
        #expect(try PropertyAssignment.parse("common.enabled=true").value == .bool(true))
        #expect(try PropertyAssignment.parse("common.enabled=false").value == .bool(false))
        #expect(try PropertyAssignment.parse("kind.fills=null").value == .null)
    }

    // MARK: - Strings

    @Test("A #hex colour stays the string the file wants")
    func hexColour() throws {
        #expect(try PropertyAssignment.parse("kind.fills=#ff8800").value == .string("#ff8800"))
    }

    @Test("A $variable stays the $-prefixed string the file wants")
    func variableReference() throws {
        #expect(try PropertyAssignment.parse("kind.fills=$brand").value == .string("$brand"))
    }

    @Test("The sizing keywords are strings")
    func sizingKeywords() throws {
        #expect(try PropertyAssignment.parse("kind.width=fill_container").value == .string("fill_container"))
        #expect(try PropertyAssignment.parse("kind.height=fit_content").value == .string("fit_content"))
    }

    @Test("Anything else is a string, spaces and all")
    func plainString() throws {
        #expect(try PropertyAssignment.parse("kind.content=Hello there").value == .string("Hello there"))
        #expect(try PropertyAssignment.parse("kind.content=").value == .string(""))
    }

    @Test("A value with an = in it keeps it: only the first = splits")
    func equalsInValue() throws {
        let assignment = try PropertyAssignment.parse("kind.content=a=b")
        #expect(assignment.key == "kind.content")
        #expect(assignment.value == .string("a=b"))
    }

    @Test("Quoting forces a string, so a name can be a number or a keyword")
    func quotedString() throws {
        #expect(try PropertyAssignment.parse("common.name=\"42\"").value == .string("42"))
        #expect(try PropertyAssignment.parse("common.name=\"true\"").value == .string("true"))
    }

    // MARK: - JSON

    @Test("A value opening with [ or { is JSON")
    func jsonValues() throws {
        #expect(try PropertyAssignment.parse("kind.padding=[8,16]").value == .array([.int(8), .int(16)]))
        #expect(
            try PropertyAssignment.parse("kind.fills={\"type\":\"solid\",\"color\":\"#fff\"}").value
                == .dictionary(["type": .string("solid"), "color": .string("#fff")])
        )
    }

    @Test("JSON that will not parse is a usage error naming the key")
    func malformedJSON() throws {
        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.parse("kind.padding=[8,")
        }
        #expect(failure?.exitCode == .usage)
        #expect(failure?.message.contains("kind.padding") == true)
    }

    // MARK: - Refusals

    @Test("A value with no = says how to write one")
    func missingEquals() throws {
        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.parse("kind.content")
        }
        #expect(failure?.exitCode == .usage)
        #expect(failure?.message.contains("key=value") == true)
    }

    @Test("An empty key is refused")
    func emptyKey() throws {
        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.parse("=12")
        }
        #expect(failure?.exitCode == .usage)
    }

    @Test("The same key twice is refused rather than silently keeping one")
    func duplicateKey() throws {
        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.properties(from: ["kind.width=1", "kind.width=2"], file: nil)
        }
        #expect(failure?.exitCode == .usage)
        #expect(failure?.message.contains("kind.width") == true)
    }

    // MARK: - Files

    @Test("-F reads a JSON object of properties, and the command line wins over it")
    func propertiesFromFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("props-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("props.json")
        try #"{"kind.width": 100, "kind.height": 50}"#.write(to: url, atomically: true, encoding: .utf8)

        let properties = try PropertyAssignment.properties(from: ["kind.width=240"], file: url.path)
        #expect(properties["kind.width"] == .int(240))
        #expect(properties["kind.height"] == .int(50))
    }

    @Test("-F pointing at something that is not an object says what it wanted")
    func fileIsNotAnObject() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("props-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("props.json")
        try "[1,2,3]".write(to: url, atomically: true, encoding: .utf8)

        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.properties(from: [], file: url.path)
        }
        #expect(failure?.exitCode == .usage)
        #expect(failure?.message.contains("JSON object") == true)
    }

    @Test("-F pointing at nothing is a target failure naming the path")
    func fileMissing() throws {
        let failure = #expect(throws: CommandFailure.self) {
            try PropertyAssignment.properties(from: [], file: "/nowhere/props.json")
        }
        #expect(failure?.exitCode == .targetFailure)
        #expect(failure?.message.contains("/nowhere/props.json") == true)
    }
}
