//
//  TextSpansOverrideCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Rich text inside an instance from a shell: `override` writes a text's spans into the
/// instance's override, refuses spans Woodcase cannot draw, and — as `set` does on a plain
/// text — warns when it changes words the instance's own spans were made for; `lint` then
/// names them on the instance.
///
/// `text-spans-instance.pen`: a `Card` component holding the text `Title` ("Make this
/// bold"), and its instance `First`.
@Suite("woodcase spans in instance overrides on the command line")
struct TextSpansOverrideCommandTests {
    private static let bold = #"kind.spans={"text":"Make this bold","runs":[{"start":10,"end":14,"fontWeight":"700"}]}"#

    private func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: "text-spans-instance.pen")
    }

    @Test("override writes spans on the instance's text and leaves the component plain")
    func overrideWritesSpans() throws {
        let fixture = try fixture()
        let run = try fixture.run("override", fixture.file.path, "First/Title", Self.bold)
        #expect(run.status == 0, "\(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Title")?.textSpans == nil)
        guard case let .ref(data)? = probe.node("First")?.kind,
              case let .dictionary(metadata)? = data.descendants?["Ttl01"]?.properties["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace],
              let spans = keys[PenMetadata.WoodcaseKey.spans.rawValue]
        else {
            Issue.record("First stores no spans for its title")
            return
        }
        #expect(try PenTextSpans(metadataValue: spans).runs == [PenTextRun(start: 10, end: 14, fontWeight: 700)])
    }

    @Test("override refuses malformed spans, naming the instance's text and an override to write")
    func overrideRefusesMalformedSpans() throws {
        let fixture = try fixture()
        let run = try fixture.run(
            "override", fixture.file.path, "First/Title", #"kind.spans={"text":"x","runs":[{"start":0,"end":1,"bold":true}]}"#
        )
        #expect(run.status != 0)
        #expect(run.stderr.contains("unknown key \"bold\""), "\(run.stderr)")
        #expect(run.stderr.contains("First/Title"), "\(run.stderr)")
        #expect(run.stderr.contains("woodcase override"), "\(run.stderr)")
    }

    @Test("override warns when it changes words the instance's own spans were made for, and lint names them")
    func overrideWarnsWhenOwnSpansGoStale() throws {
        let fixture = try fixture()
        _ = try fixture.run("override", fixture.file.path, "First/Title", Self.bold)
        let run = try fixture.run("override", fixture.file.path, "First/Title", "content=Other words")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stderr.contains("spans-stale"), "\(run.stderr)")
        #expect(run.stderr.contains("--unset kind.spans"), "\(run.stderr)")

        let lint = try fixture.run("lint", fixture.file.path)
        #expect(lint.stdout.contains("spans-stale  First/Title (Ins01/Ttl01)"), "\(lint.stdout)")
    }

    @Test("override says nothing when the instance gives the text no spans of its own")
    func overrideQuietWithoutOwnSpans() throws {
        let fixture = try fixture()
        let run = try fixture.run("override", fixture.file.path, "First/Title", "content=Other words")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stderr.isEmpty, "\(run.stderr)")
    }
}
