//
//  DesignTopicClaimsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// Every rule `woodcase help design` states about names, values, reads and the loop,
/// run against a file.
///
/// A help test that only greps for a sentence proves the sentence is *there*, not that
/// it is *true* — and the Quill run's most expensive hour went on a message that was
/// there and false. So each test here does both halves: it asserts the topic still makes
/// the claim, and then it runs the claim's own command against a fixture and checks the
/// promised outcome. A behavior that changes under the topic breaks this file.
///
/// The component half — instances, overrides, slots — is in
/// ``DesignTopicComponentClaimsTests``.
@Suite("What `help design` claims about names, values and reads")
struct DesignTopicClaimsTests {
    // MARK: - Names

    @Test("Two same-named cousins are fine, and one more segment tells them apart")
    func cousinsCostOneSegment() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "one more segment")

        let added = try fixture.run(
            ["add", fixture.file.path, "Page", "-F", "-", "--as", "ana"],
            stdin: Data(##"{"type":"text","name":"Title","content":"cousin","fill":"#111111"}"##.utf8)
        )
        #expect(added.status == 0)

        let ambiguous = try fixture.run("get", fixture.file.path, "Title")
        #expect(ambiguous.status == 2)
        #expect(ambiguous.stderr.contains("Card/Title"), "the candidates are not listed by full path")
        #expect(ambiguous.stderr.contains("Page/Title"), "the candidates are not listed by full path")

        let resolved = try fixture.run("get", fixture.file.path, "Page/Title")
        #expect(resolved.status == 0, "one more segment did not resolve the ambiguity")
    }

    @Test("`lint` reports same-named siblings, and leaves same-named cousins alone")
    func duplicateNameIsScopedToSiblings() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "unique among its siblings")

        let cousin = try fixture.run(
            ["add", fixture.file.path, "Page", "-F", "-", "--as", "ana"],
            stdin: Data(##"{"type":"text","name":"Title","content":"cousin","fill":"#111111"}"##.utf8)
        )
        #expect(cousin.status == 0)
        let afterCousin = try fixture.run("lint", fixture.file.path)
        #expect(
            !afterCousin.stdout.contains("duplicate-name"),
            "a same-named cousin was reported as a duplicate"
        )

        let sibling = try fixture.run(
            ["add", fixture.file.path, "Card", "-F", "-", "--as", "ana"],
            stdin: Data(##"{"type":"text","name":"Title","content":"sibling","fill":"#111111"}"##.utf8)
        )
        #expect(sibling.status == 0)
        let afterSibling = try fixture.run("lint", fixture.file.path)
        #expect(afterSibling.stdout.contains("duplicate-name"), "same-named siblings were not reported")
    }

    // MARK: - Values

    @Test("kind.lineHeight is a multiple of kind.fontSize, not a length in points")
    func lineHeightIsAMultiplier() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "multiple of kind.fontSize")

        let sized = try fixture.run(
            "set", fixture.file.path, "Card/Title",
            "kind.fontSize=10", "kind.height=fit_content", "--as", "ana"
        )
        #expect(sized.status == 0)
        let single = try Self.height(of: "Card/Title", in: fixture)

        let leaded = try fixture.run("set", fixture.file.path, "Card/Title", "kind.lineHeight=5", "--as", "ana")
        #expect(leaded.status == 0)
        let quintupled = try Self.height(of: "Card/Title", in: fixture)

        // Five points of leading would have shrunk the box; five times the 10pt font
        // multiplies it. Only the multiplier reading puts the answer near 50.
        #expect(single < 25, "a single 10pt line settled at \(single)pt")
        #expect(quintupled > 40, "lineHeight 5 on a 10pt font settled at \(quintupled)pt, not a multiple")
    }

    @Test("`woodcase schema text` says lineHeight is a multiple of fontSize")
    func schemaSaysLineHeightIsAMultiple() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let run = try fixture.run("schema", "text")
        #expect(run.status == 0)
        #expect(
            run.stdout.contains("multiple of fontSize"),
            "the schema's lineHeight row does not say it is a multiple of fontSize"
        )
    }

    @Test(##"\$ keeps a literal $ out of the variable table"##)
    func dollarEscapeStoresALiteral() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: ##"'\$120,000'"##)

        #expect(try fixture.run(
            "vars", "set", fixture.file.path, "--as", "ana", "--", "--price=SALE"
        ).status == 0)

        // A bare $name the document defines substitutes; the escape keeps the text.
        #expect(try fixture.run(
            "set", fixture.file.path, "Card/Title", "kind.content=$--price", "--as", "ana"
        ).status == 0)
        let substituted = try fixture.run("tree", fixture.file.path, "Card/Title", "--props", "kind.content")
        #expect(substituted.stdout.contains("SALE"), "a defined $name did not substitute")

        #expect(try fixture.run(
            "set", fixture.file.path, "Card/Title", ##"kind.content=\$--price"##, "--as", "ana"
        ).status == 0)
        let literal = try fixture.run("tree", fixture.file.path, "Card/Title", "--props", "kind.content")
        #expect(!literal.stdout.contains("SALE"), "the escape did not keep the literal")

        // Outside text content, a $name naming nothing stays a dangling reference.
        #expect(try fixture.run(
            "set", fixture.file.path, "Card/Title", "kind.fills=$--nope", "--as", "ana"
        ).status == 0)
        let dirty = try fixture.run("lint", fixture.file.path)
        #expect(
            dirty.stdout.contains("unresolved-variable"),
            "a dangling reference in a color property was not linted"
        )
    }

    @Test("A dash-prefixed variable name needs the bare `--` the topic shows")
    func dashPrefixedNamesNeedTheSeparator() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "woodcase vars set f.pen -- --accent=#e0561a")

        let withoutSeparator = try fixture.run("vars", "set", fixture.file.path, "--accent=#e0561a", "--as", "ana")
        #expect(withoutSeparator.status == 2, "a dash-prefixed name parsed without the separator")
        #expect(withoutSeparator.stderr.contains("bare --"), "the refusal does not name the rule the topic states")

        let withSeparator = try fixture.run(
            "vars", "set", fixture.file.path, "--as", "ana", "--", "--accent=#e0561a"
        )
        #expect(withSeparator.status == 0, "the form the topic shows does not run: \(withSeparator.stderr)")
        #expect(withSeparator.stdout.contains("--accent"))
    }

    // MARK: - Reads

    @Test("--props takes a comma-separated list of property paths")
    func propsTakesACommaList() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "--props kind.content,common.name")

        let run = try fixture.run("tree", fixture.file.path, "Card", "--props", "kind.content,common.name")
        #expect(run.status == 0)
        #expect(run.stdout.contains("kind.content"), "the kind.content column is missing")
        #expect(run.stdout.contains("common.name"), "the common.name column is missing")
    }

    @Test("Rects are parent-relative unless --absolute, and --json carries both")
    func rectsAreParentRelativeUnlessAbsolute() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "parent-relative")

        let relative = try fixture.run("tree", fixture.file.path, "Page/Hole")
        #expect(relative.status == 0)
        #expect(relative.stdout.contains("400,0"), "Page/Hole's parent-relative rect is 400,0")

        let absolute = try fixture.run("tree", fixture.file.path, "Page/Hole", "--absolute")
        #expect(absolute.status == 0)
        #expect(absolute.stdout.contains("700,0"), "Page/Hole's document-space rect is 700,0")

        let json = try fixture.run("tree", fixture.file.path, "Page/Hole", "--json")
        #expect(json.stdout.contains("absRect"), "--json carries no absRect")
        #expect(json.stdout.contains("\"rect\""), "--json carries no rect")
    }

    // MARK: - Fonts

    @Test("The topic names the font cache, and a read that misses names the same directory")
    func fontCacheIsUnderWoodcaseHome() throws {
        let fixture = try CommandFixture(fixture: "font-missing.pen")
        try Self.expectDesignTopic(fixture, teaches: "$WOODCASE_HOME/fonts")

        let run = try fixture.run("tree", fixture.file.path)
        #expect(run.status == 0)
        #expect(
            run.stderr.contains(fixture.home.appendingPathComponent("fonts").path),
            "the fallback notice does not name the directory the topic promises"
        )
    }

    // MARK: - The loop

    @Test("A repeated write-then-measure is a `js` program, and the loop section says so")
    func aRepeatedMeasureAndFixLoopIsAProgram() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let run = try fixture.run("help", "design")
        #expect(run.status == 0)
        // The sentence has to sit in THE LOOP section itself, where an agent about to
        // run the loop a second time is reading, not in the batches paragraph.
        let loop = try #require(run.stdout.range(of: "THE LOOP"), "the topic has no loop section")
        let foot = try #require(run.stdout.range(of: "SEE ALSO"), "the topic has no see-also foot")
        let section = run.stdout[loop.upperBound ..< foot.lowerBound]
        #expect(
            section.contains("that loop is a `js` program"),
            "the loop section does not hand a repeated write-then-measure to `js`"
        )

        // And it is true: one js run writes, measures what it just made, and decides.
        let program = """
        const before = doc.tree('Card/Title')[0].rect.height;
        doc.set('Card/Title', {
          'kind.height': 'fit_content',
          'kind.content': 'A much longer title that wraps onto a second line at this width',
        });
        const after = doc.tree('Card/Title')[0].rect.height;
        if (after <= before) throw new Error('the write did not grow the box: ' + before + ' -> ' + after);
        """
        let scriptPath = fixture.root.appendingPathComponent("measure.js").path
        try program.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let ran = try fixture.run("js", fixture.file.path, "-F", scriptPath, "--as", "ana")
        #expect(ran.status == 0, "the loop the topic describes does not run: \(ran.stderr)")
    }

    @Test("`activity` is the fourth step, and `undo` is per writer")
    func undoIsPerWriterAndActivityShowsWho() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "woodcase activity")

        #expect(try fixture.run("set", fixture.file.path, "Card/Title", "kind.content=A", "--as", "ana").status == 0)
        #expect(try fixture.run("set", fixture.file.path, "Card/Title", "kind.content=B", "--as", "bo").status == 0)

        let log = try fixture.run("activity", fixture.file.path)
        #expect(log.status == 0)
        #expect(log.stdout.contains("ana"), "the activity log does not name ana")
        #expect(log.stdout.contains("bo"), "the activity log does not name bo")

        let refused = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(refused.status != 0, "undo crossed identities without --all")
        #expect(refused.stderr.contains("bo"), "the refusal does not name the later writer")

        let crossed = try fixture.run("undo", fixture.file.path, "--as", "ana", "--all")
        #expect(crossed.status == 0, "--all did not undo across identities")
    }

    // MARK: - The foot

    @Test("The topic ends by naming the verbs whose help carries what it does not")
    func theTopicPointsOnward() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let run = try fixture.run("help", "design")
        #expect(run.stdout.contains("SEE ALSO"), "the topic has no see-also foot")
        for verb in ["override", "cp", "apply", "shot", "replace", "lint"] {
            #expect(
                run.stdout.contains("`\(verb) --help`") || run.stdout.contains("\(verb) --help"),
                "the see-also foot does not name \(verb)"
            )
        }
        #expect(run.stdout.contains("help recipes"), "the see-also foot does not name help recipes")
    }

    // MARK: - Helpers

    /// Asserts `woodcase help design` still carries a claim, before the claim is tested.
    ///
    /// - Parameters:
    ///   - fixture: The fixture whose binary to run.
    ///   - phrase: The wording the topic must still contain.
    /// - Throws: Whatever launching the binary throws.
    private static func expectDesignTopic(_ fixture: CommandFixture, teaches phrase: String) throws {
        let run = try fixture.run("help", "design")
        #expect(run.status == 0)
        #expect(run.stdout.contains(phrase), "`help design` no longer says \(phrase)")
    }

    /// The settled height of one node, read from `tree --json`.
    ///
    /// - Parameters:
    ///   - address: The node to read.
    ///   - fixture: The fixture holding the file.
    /// - Returns: The height in points.
    /// - Throws: Whatever launching the binary throws.
    private static func height(of address: String, in fixture: CommandFixture) throws -> Double {
        let run = try fixture.run("tree", fixture.file.path, address, "--json")
        #expect(run.status == 0)
        guard let object = try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any],
              let rows = object["rows"] as? [[String: Any]],
              let rect = rows.first?["rect"] as? [String: Any],
              let height = rect["height"] as? Double
        else {
            Issue.record("tree --json carried no rect for \(address): \(run.stdout)")
            return 0
        }
        return height
    }
}
