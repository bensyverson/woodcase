//
//  FindCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase find` — `tree`'s rows, filtered by a JavaScript predicate.
///
/// Drives the built binary, because the whole contract is what a shell sees: the rows
/// on stdout, the sentence on stderr, and the exit status a `find … && …` branches on.
@Suite("woodcase find")
struct FindCommandTests {
    // MARK: - The answer

    @Test("matching rows print in tree's format, under tree's header")
    func matchingRowsPrint() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.type === 'text'")

        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("rev "))
        #expect(lines[0].hasSuffix("2 rows"))
        #expect(lines[1].hasSuffix("Ttl01"))
        #expect(lines[2].hasSuffix("Lbl01"))
    }

    @Test("no matches exits 1 with nothing on stdout")
    func noMatchesIsACleanNegative() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.type === 'ellipse'")

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
    }

    @Test("no matches prints nothing with --json either: the exit code is the answer")
    func noMatchesIsSilentInJSON() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => false", "--json")

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
    }

    @Test("--json is tree's report, carrying only the rows that matched")
    func jsonIsATreeReport() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.type === 'text'", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        #expect(report.rows.map(\.id) == ["Ttl01", "Lbl01"])
        #expect(!report.revision.isEmpty)
    }

    // MARK: - Parity with tree

    @Test("a predicate that keeps everything prints exactly what tree prints")
    func everythingEqualsTree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let found = try fixture.run("find", fixture.file.path, "r => true")
        let listed = try fixture.run("tree", fixture.file.path)

        #expect(found.status == 0)
        #expect(found.stdout == listed.stdout)
    }

    @Test("--json parity too, byte for byte")
    func everythingEqualsTreeJSON() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let found = try fixture.run("find", fixture.file.path, "r => true", "--json")
        let listed = try fixture.run("tree", fixture.file.path, "--json")

        #expect(found.stdout == listed.stdout)
    }

    @Test("a matching subset is the same bytes tree's formatter renders for those rows")
    func aSubsetIsTheFormattersOwnBytes() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.type === 'text'")

        let document = try EditableDocument(from: PenParser.parse(contentsOf: fixture.file))
        let matching = try TreeView.rows(of: document).filter { $0.type == "text" }
        let expected = "rev \(document.documentRevision)  2 rows\n"
            + TreeFormatter.text(matching) + "\n"
        #expect(run.stdout == expected)
    }

    @Test("--expand, --absolute and --props reach the rows the same way tree's do")
    func flagsMatchTree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let found = try fixture.run(
            "find", fixture.file.path, "r => true",
            "--expand", "--absolute", "--props", "kind.content"
        )
        let listed = try fixture.run(
            "tree", fixture.file.path,
            "--expand", "--absolute", "--props", "kind.content"
        )

        #expect(found.stdout == listed.stdout)
    }

    @Test("an address scopes the walk, as tree's does")
    func anAddressScopesTheWalk() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let found = try fixture.run("find", fixture.file.path, "Board", "r => true")
        let listed = try fixture.run("tree", fixture.file.path, "Board")

        #expect(found.status == 0)
        #expect(found.stdout == listed.stdout)
    }

    @Test("an address that resolves to nothing is a usage error, as it is for tree")
    func anUnresolvableAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "Nowhere", "r => true")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
    }

    // MARK: - Where the predicate comes from

    @Test("-F reads a predicate that outgrew a line")
    func predicateFromAFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let script = fixture.root.appendingPathComponent("wide.js")
        try Data("""
        r =>
          r.type === 'text' &&
          r.depth === 1
        """.utf8).write(to: script)

        let run = try fixture.run("find", fixture.file.path, "-F", script.path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
    }

    @Test("-F - reads the predicate from standard input")
    func predicateFromStandardInput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            ["find", fixture.file.path, "-F", "-"],
            stdin: Data("r => r.id === 'Brd01'".utf8)
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 2)
        #expect(run.stdoutLines[1].hasSuffix("Brd01"))
    }

    @Test("a predicate given twice is refused rather than one of them being ignored")
    func twoPredicatesAreRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let script = fixture.root.appendingPathComponent("p.js")
        try Data("r => true".utf8).write(to: script)

        let run = try fixture.run(
            "find", fixture.file.path, "Board", "r => true", "-F", script.path
        )

        #expect(run.status == 2)
        #expect(run.stderr.contains("-F"))
    }

    @Test("with -F the one operand is the subtree, because the predicate is already given")
    func withAFileTheOperandIsTheSubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let script = fixture.root.appendingPathComponent("p.js")
        try Data("r => true".utf8).write(to: script)

        let found = try fixture.run("find", fixture.file.path, "Board", "-F", script.path)
        let listed = try fixture.run("tree", fixture.file.path, "Board")

        #expect(found.status == 0)
        #expect(found.stdout == listed.stdout)
    }

    @Test("no predicate at all points at tree, which is the listing find filters")
    func noPredicateIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path)

        #expect(run.status == 2)
        #expect(run.stderr.contains("tree"))
    }

    // MARK: - Errors that teach

    @Test("a property outside r.props exits 2, naming the row and listing the members")
    func unknownMemberTeaches() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.fontSize < 12")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Cnv01"))
        #expect(run.stderr.contains("Canvas"))
        #expect(run.stderr.contains("r.props"))
        #expect(run.stderr.contains("absRect"))
    }

    @Test("a predicate cannot reach doc, and is sent to js for it")
    func docIsOutOfReach() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => doc")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("doc"))
        #expect(run.stderr.contains("js"))
    }

    @Test("a predicate that does not parse exits 2 with the line and the message")
    func aSyntaxErrorTeaches() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => (")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("line 1"))
        #expect(run.stderr.contains("r => ("))
    }

    @Test("a predicate written as a bare expression names the arrow-function shape, not the reference error")
    func aBareExpressionTeachesTheShape() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, #"r.type === "text""#)

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("arrow function of one row"))
        #expect(run.stderr.contains("r => "))
        #expect(!run.stderr.contains("Can't find variable"))
    }

    @Test("r.props with no --props says which flag would fill it")
    func propsNeedsTheFlag() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.props['kind.fontSize'] < 12")

        #expect(run.status == 2)
        #expect(run.stderr.contains("--props"))
    }

    @Test("a file that cannot be read is a target failure, as it is for every verb")
    func anUnreadableFileIsFour() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let missing = fixture.root.appendingPathComponent("nope.pen")
        let run = try fixture.run("find", missing.path, "r => true")

        #expect(run.status == 4)
    }

    // MARK: - The property columns

    @Test("--props widens the listing and feeds the predicate at once")
    func propsFeedThePredicate() throws {
        let fixture = try CommandFixture(fixture: "banking.pen")
        let run = try fixture.run(
            "find", fixture.file.path,
            "r => r.type === 'text' && r.props['kind.fontSize'] < 13",
            "--props", "kind.fontSize"
        )

        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines.count > 2)
        #expect(lines[1].contains("kind.fontSize"))
        for row in lines.dropFirst(2) {
            #expect(row.hasPrefix("text"))
        }
    }

    @Test("a --props path no row carries is called out on stderr, as tree calls it out")
    func anEmptyColumnIsCalledOut() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            "find", fixture.file.path, "r => r.props['kind.fontsize'] !== undefined",
            "--props", "kind.fontsize"
        )

        #expect(run.status == 1)
        #expect(run.stderr.contains("kind.fontsize"))
    }
}
