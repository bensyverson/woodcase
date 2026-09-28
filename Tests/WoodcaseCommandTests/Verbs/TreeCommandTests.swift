//
//  TreeCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase tree` — the read an agent runs first.
///
/// Drives the built binary, because the subject is exactly what an agent sees: the
/// bytes on stdout, the message on stderr and the exit status.
@Suite("woodcase tree")
struct TreeCommandTests {
    // MARK: - The outline

    @Test("A bare read prints a revision header and one row per node")
    func rowsForEveryNode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        let lines = run.stdoutLines
        // Cnv01, Ttl01, Crd01, Cd101, Cd201, Brd01, Chi01, Cmp01, Lbl01.
        #expect(lines.count == 10)
        #expect(lines[0].hasPrefix("rev "))
        #expect(lines[0].hasSuffix("9 rows"))
        for name in ["Canvas", "Title", "Cards", "First", "Second", "Board", "Chip", "Component", "Label"] {
            #expect(lines.dropFirst().contains { $0.contains(name) }, "no row for \(name)")
        }
    }

    @Test("Every row carries its settled rect and its id")
    func rowsCarryRectAndID() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path)

        let canvas = try #require(run.stdoutLines.first { $0.contains("Canvas") })
        #expect(canvas.contains("frame"))
        #expect(canvas.contains("0,0 400×300"))
        #expect(canvas.hasSuffix("Cnv01"))
    }

    @Test("A child that leaves its parent is flagged, partially and fully")
    func clipFlags() throws {
        let fixture = try CommandFixture(fixture: "tree-overflow.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 5)
        let overflowing = try #require(run.stdoutLines.first { $0.contains("overflows") })
        #expect(overflowing.contains("⚠ partial"))
        let outside = try #require(run.stdoutLines.first { $0.contains("Out01") })
        #expect(outside.contains("⚠ clipped"))
        let fitting = try #require(run.stdoutLines.first { $0.contains("fits") })
        #expect(!fitting.contains("⚠"))
    }

    @Test("The header's revision is the document revision --rev will be checked against")
    func headerCarriesTheDocumentRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let text = try fixture.run("tree", fixture.file.path)
        let json = try fixture.run("tree", fixture.file.path, "--json")

        let report = try JSONDecoder().decode(TreeReport.self, from: Data(json.stdout.utf8))
        #expect(text.stdoutLines[0] == "rev \(report.revision)  9 rows")
    }

    // MARK: - Scope

    @Test("A node argument scopes the listing to that subtree")
    func subtreeListing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "Board")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
        #expect(run.stdoutLines[0].hasSuffix("2 rows"))
        #expect(run.stdoutLines[1].contains("Board"))
        #expect(run.stdoutLines[2].contains("Chip"))
    }

    @Test("--depth limits the walk and the hidden children are counted")
    func depthLimit() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--depth", "0")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 4)
        let canvas = try #require(run.stdoutLines.first { $0.contains("Canvas") })
        #expect(canvas.contains("+2"))
    }

    @Test("A negative --depth is a usage error naming the flag")
    func negativeDepthIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--depth=-1")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--depth"))
    }

    @Test("--expand walks into an instance, addressing its nodes by id path")
    func expandInstances() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "Board", "--expand")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 4)
        #expect(run.stdoutLines[3].contains("Chi01/Lbl01"))
    }

    @Test("--props adds a labelled column per property path")
    func propertyColumns() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props", "kind.content,common.name")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(run.stdoutLines[0].hasPrefix("rev "))
        #expect(run.stdoutLines[1].hasPrefix("type"))
        #expect(run.stdoutLines[1].contains("kind.content"))
        let title = try #require(run.stdoutLines.first { $0.contains("Ttl01") })
        #expect(title.contains("Canvas"))
        #expect(title.hasSuffix("Title"))
    }

    @Test("A bare --props widens the listing with the default columns instead of erroring")
    func barePropertyColumns() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props")

        #expect(run.status == 0)
        let heading = try #require(run.stdoutLines.dropFirst().first)
        #expect(heading.hasPrefix("type"))
        for path in Tree.defaultPropertyPaths {
            #expect(heading.contains(path), "the default columns omit \(path)")
        }
    }

    @Test("A default column nothing carries is not called out — the caller named no path")
    func barePropertyColumnsAreSilent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props")

        #expect(run.stderr.isEmpty)
    }

    @Test("A --props path no node carries is called out on stderr, not left as dashes")
    func emptyPropertyColumnIsCalledOut() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props", "content")

        #expect(run.status == 0)
        #expect(run.stdoutLines[1].contains("content"))
        #expect(run.stderr.contains("no node in this listing has \"content\""))
        #expect(run.stderr.contains("kind.content"))
    }

    @Test("--props on an unexpanded instance still says the property grammar, and also says --expand")
    func emptyPropertyColumnOnAnUnexpandedInstanceSuggestsExpand() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "Board/Chip", "--props", "kind.content")

        #expect(run.status == 0)
        #expect(run.stderr.contains("no node in this listing has \"kind.content\""))
        #expect(run.stderr.contains("common.name"))
        #expect(run.stderr.contains("--expand"))
    }

    @Test("--props naming an empty column with --expand already given does not suggest --expand again")
    func emptyPropertyColumnWithExpandAlreadyGivenDoesNotSuggestItAgain() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "Board/Chip", "--expand", "--props", "kind.layout")

        #expect(run.status == 0)
        #expect(run.stderr.contains("no node in this listing has \"kind.layout\""))
        #expect(!run.stderr.contains("--expand"))
    }

    // MARK: - JSON

    @Test("--json is machine-parseable and decodes as the library's own report")
    func jsonIsParseable() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        #expect(report.rows.count == 9)
        #expect(report.revision.count == 16)
        let chip = try #require(report.rows.first { $0.id == "Chi01" })
        #expect(chip.type == "ref")
        #expect(chip.isInstance)
        #expect(chip.address == "Board/Chip")
    }

    // MARK: - Errors

    @Test("An address that names nothing exits 2 and lists near misses")
    func unknownAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "Nope")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Nope"))
    }

    @Test("An ambiguous address exits 2 and lists every candidate")
    func ambiguousAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("tree", fixture.file.path, "Title")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Ttl01"))
        #expect(run.stderr.contains("Ttl02"))
    }

    @Test("A malformed --theme pin exits 2 and quotes the pin")
    func malformedThemePinIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--theme", "mode")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("mode"))
    }

    @Test("A file that is not there exits 4")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.root.appendingPathComponent("gone.pen").path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("gone.pen"))
    }

    @MainActor
    @Test("Every --json row carries the node's own revision")
    func jsonRowsCarryRevisions() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        #expect(report.rows.allSatisfy { $0.rev.count == 16 })

        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        for row in report.rows {
            #expect(row.rev == document.revision(of: row.id), "rev mismatch for \(row.id)")
        }
    }

    @Test("A row's rev is the token get hands back for the same node")
    func rowRevMatchesGet() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let tree = try fixture.run("tree", fixture.file.path, "--json")
        let get = try fixture.run("get", fixture.file.path, "Cards", "--json")

        let report = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8))
        let node = try JSONDecoder().decode(NodeReport.self, from: Data(get.stdout.utf8))
        let cards = try #require(report.rows.first { $0.id == "Crd01" })
        #expect(cards.rev == node.revision)
    }

    @Test("Two separate processes reading the same bytes print identical revisions")
    func revisionsAgreeAcrossProcesses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let first = try fixture.run("tree", fixture.file.path, "--json")
        let second = try fixture.run("tree", fixture.file.path, "--json")

        let one = try JSONDecoder().decode(TreeReport.self, from: Data(first.stdout.utf8))
        let two = try JSONDecoder().decode(TreeReport.self, from: Data(second.stdout.utf8))
        #expect(one.revision == two.revision)
        #expect(one.rows.map(\.rev) == two.rows.map(\.rev))
        #expect(!one.rows.isEmpty)
    }

    @Test("A write moves the rev of the node it touched and of its ancestors, and no others")
    func aWriteMovesTheSpineOnly() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try JSONDecoder().decode(
            TreeReport.self, from: Data(fixture.run("tree", fixture.file.path, "--json").stdout.utf8)
        )
        let write = try fixture.run("set", fixture.file.path, "Canvas/Cards/First", "kind.width=140")
        #expect(write.status == 0)
        let after = try JSONDecoder().decode(
            TreeReport.self, from: Data(fixture.run("tree", fixture.file.path, "--json").stdout.utf8)
        )

        let spine: Set = ["Cd101", "Crd01", "Cnv01"]
        let old = before.rows.reduce(into: [String: String]()) { $0[$1.id] = $1.rev }
        let new = after.rows.reduce(into: [String: String]()) { $0[$1.id] = $1.rev }
        #expect(old.keys.sorted() == new.keys.sorted())
        for id in old.keys.sorted() {
            if spine.contains(id) {
                #expect(new[id] != old[id], "\(id) is on the spine and should have moved")
            } else {
                #expect(new[id] == old[id], "\(id) is off the spine and should not have moved")
            }
        }
    }

    @Test("A definition edit moves every instance's row, and every ancestor above one")
    func aDefinitionEditMovesInstanceRows() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try JSONDecoder().decode(
            TreeReport.self, from: Data(fixture.run("tree", fixture.file.path, "--json").stdout.utf8)
        )
        let write = try fixture.run("set", fixture.file.path, "Component/Label", "kind.content=chipped")
        #expect(write.status == 0)
        let after = try JSONDecoder().decode(
            TreeReport.self, from: Data(fixture.run("tree", fixture.file.path, "--json").stdout.utf8)
        )

        // A ref's rev folds in the component it renders, so the definition's spine and
        // the instance's both move; the unrelated Canvas branch does not.
        let moved: Set = ["Lbl01", "Cmp01", "Chi01", "Brd01"]
        let old = before.rows.reduce(into: [String: String]()) { $0[$1.id] = $1.rev }
        let new = after.rows.reduce(into: [String: String]()) { $0[$1.id] = $1.rev }
        for id in old.keys.sorted() {
            if moved.contains(id) {
                #expect(new[id] != old[id], "\(id) renders the edited definition and should have moved")
            } else {
                #expect(new[id] == old[id], "\(id) does not render it and should not have moved")
            }
        }
    }

    @Test("A read leaves the file's bytes exactly as they were")
    func readsNeverWrite() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        _ = try fixture.run("tree", fixture.file.path, "--expand")

        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
