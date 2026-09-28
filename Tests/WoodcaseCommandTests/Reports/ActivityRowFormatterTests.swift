//
//  ActivityRowFormatterTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The one-line-per-event outline `woodcase activity` prints in its default form.
@Suite("Activity row formatting")
struct ActivityRowFormatterTests {
    private static let utc = TimeZone(identifier: "UTC")!

    private static func event(
        time: String = "2026-01-01T16:31:04.000Z",
        identity: String = "ana",
        op: ActivityEvent.Kind = .set,
        paths: [String] = ["layout-vertical/first"]
    ) throws -> ActivityEvent {
        let date = try Date(time, strategy: ActivityEvent.timeFormat)
        return ActivityEvent(
            time: date,
            identity: identity,
            file: URL(fileURLWithPath: "/tmp/demo.pen"),
            op: op,
            nodes: paths.map { _ in "someID" },
            paths: paths,
            revision: "rev1"
        )
    }

    /// Splits a row into its four `" | "`-separated columns.
    private static func columns(of row: String) -> [String] {
        row.components(separatedBy: " | ")
    }

    @Test("A row has four columns: time, identity, verb, path")
    func rendersFourColumns() throws {
        let row = try ActivityRowFormatter.row(for: Self.event(), timeZone: Self.utc)
        let parts = Self.columns(of: row)

        #expect(parts.count == 4)
        #expect(parts[0] == "16:31:04")
        #expect(parts[1] == "ana")
        #expect(parts[2].trimmingCharacters(in: .whitespaces) == "set")
        #expect(parts[3] == "layout-vertical/first")
    }

    @Test("The time column reflects the given time zone")
    func timeReflectsTimeZone() throws {
        let event = try Self.event(time: "2026-01-01T16:31:04.000Z")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))

        let utcRow = ActivityRowFormatter.row(for: event, timeZone: Self.utc)
        let nyRow = ActivityRowFormatter.row(for: event, timeZone: newYork)

        #expect(Self.columns(of: utcRow)[0] == "16:31:04")
        #expect(Self.columns(of: nyRow)[0] == "11:31:04")
    }

    @Test("The verb column is padded to the widest Kind, every row the same width")
    func verbColumnIsFixedWidth() throws {
        let short = try Self.event(op: .cp)
        let long = try Self.event(op: .override)

        let shortVerb = Self.columns(of: ActivityRowFormatter.row(for: short, timeZone: Self.utc))[2]
        let longVerb = Self.columns(of: ActivityRowFormatter.row(for: long, timeZone: Self.utc))[2]

        #expect(shortVerb.count == ActivityRowFormatter.verbColumnWidth)
        #expect(longVerb.count == ActivityRowFormatter.verbColumnWidth)
        #expect(longVerb.trimmingCharacters(in: .whitespaces) == "override")
        #expect(ActivityEvent.Kind.allCases.map(\.rawValue.count).max() == ActivityRowFormatter.verbColumnWidth)
    }

    @Test("Several paths show the first, plus a +N count of the rest")
    func multiplePathsShowFirstPlusCount() throws {
        let event = try Self.event(paths: ["a/one", "a/two", "a/three"])
        let path = Self.columns(of: ActivityRowFormatter.row(for: event, timeZone: Self.utc))[3]

        #expect(path == "a/one +2")
    }

    @Test("An event that touches no node shows - in the path column")
    func noPathsShowDash() throws {
        let event = try Self.event(paths: [])
        let path = Self.columns(of: ActivityRowFormatter.row(for: event, timeZone: Self.utc))[3]

        #expect(path == "-")
    }

    @Test("text(_:) joins rows in the order given, with no trailing newline")
    func textJoinsRowsInOrder() throws {
        let first = try Self.event(op: .set)
        let second = try Self.event(op: .rm)

        let text = ActivityRowFormatter.text([first, second], timeZone: Self.utc)
        let lines = text.components(separatedBy: "\n")

        #expect(lines.count == 2)
        #expect(lines[0].contains("set"))
        #expect(lines[1].contains("rm"))
        #expect(!text.hasSuffix("\n"))
    }

    @Test("text(_:) of an empty list is empty")
    func textOfEmptyListIsEmpty() {
        #expect(ActivityRowFormatter.text([], timeZone: Self.utc).isEmpty)
    }
}
