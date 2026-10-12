//
//  CommentCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase comment` — starting a thread, so an agent never writes the comment keys by
/// hand. Penumbra's notes design rev 2, decision 8 and Ben's session 12 rulings.
@Suite("woodcase comment starts a thread")
struct CommentCommandTests {
    /// The root node with an id, from the file as written.
    private func root(_ id: String, in fixture: CommandFixture) throws -> PenNode {
        try #require(PenFileProbe(fixture.file).roots.first { $0.id == id })
    }

    /// A node's `metadata.woodcase` keys.
    private func keys(_ node: PenNode) throws -> [String: AnyCodable] {
        guard case let .dictionary(keys)? = node.common.metadata?.extensions[PenMetadata.woodcaseNamespace] else {
            Issue.record("\(node.id) has no woodcase metadata")
            return [:]
        }
        return keys
    }

    @Test("comment writes a root note: comment type, author, createdAt, open, anchor in the node's coordinates")
    func startsThread() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let before = Date().addingTimeInterval(-1)
        let run = try fixture.run(
            "comment", fixture.file.path, "Card1", "--at", "12,4", "Is the **padding** right?", "--as", "claude"
        )
        let after = Date().addingTimeInterval(1)

        #expect(run.status == 0, "comment refused: \(run.stderr)")
        let first = try #require(run.stdoutLines.first)
        #expect(first.hasPrefix("thread  "))
        let id = try #require(first.split(separator: " ").last.map(String.init))
        #expect(run.stdoutLines.contains { $0.hasPrefix("rev  ") })

        let note = try root(id, in: fixture)
        guard case let .note(data) = note.kind else {
            Issue.record("\(id) is not a note")
            return
        }
        #expect(data.content == .literal("Is the **padding** right?"))
        let keys = try keys(note)
        #expect(keys["type"] == .string("comment"))
        #expect(keys["author"] == .string("claude"))
        #expect(keys["state"] == .string("open"))
        #expect(keys["anchor"] == .dictionary(["node": .string("Card1"), "x": .int(12), "y": .int(4)]))
        guard case let .string(createdAt)? = keys["createdAt"] else {
            Issue.record("no createdAt string: \(String(describing: keys["createdAt"]))")
            return
        }
        let date = try #require(PenComment.date(createdAt: createdAt))
        #expect(date >= before.addingTimeInterval(-1) && date <= after)
    }

    @Test("A name path to an instance child is stored as the expanded id path; --at defaults to its top-left")
    func instanceChild() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run(
            "comment", fixture.file.path, "Dashboard/Body/Nav/Label", "Wrong label", "--id", "CmLbl", "--as", "ana"
        )

        #expect(run.status == 0, "comment refused: \(run.stderr)")
        #expect(try keys(root("CmLbl", in: fixture))["anchor"]
            == .dictionary(["node": .string("Nav01/Lbl01"), "x": .int(0), "y": .int(0)]))
    }

    @Test("Without a node the point is in page coordinates, and the anchor has no node")
    func canvas() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let bare = try fixture.run("comment", fixture.file.path, "--at", "900,40.5", "A legend?", "--id", "CmA", "--as", "ana")
        let flagged = try fixture.run(
            "comment", fixture.file.path, "--canvas", "--at", "10,20", "Here", "--id", "CmB", "--as", "ana"
        )

        #expect(bare.status == 0, "comment refused: \(bare.stderr)")
        #expect(flagged.status == 0, "comment refused: \(flagged.stderr)")
        #expect(try keys(root("CmA", in: fixture))["anchor"] == .dictionary(["x": .int(900), "y": .double(40.5)]))
        #expect(try keys(root("CmB", in: fixture))["anchor"] == .dictionary(["x": .int(10), "y": .int(20)]))
    }

    @Test("A canvas comment without --at is refused: there is no point to mark")
    func canvasNeedsAPoint() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comment", fixture.file.path, "Btn01", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("--at"), "stderr: \(run.stderr)")
    }

    @Test("--canvas with a node is refused")
    func canvasWithNode() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comment", fixture.file.path, "Btn01", "Hi", "--canvas", "--at", "1,1", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stderr.contains("drop --canvas"), "stderr: \(run.stderr)")
    }

    @Test("A node that is not there is refused with the near misses, and nothing is written")
    func missingNode() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let original = try Data(contentsOf: fixture.file)
        let run = try fixture.run("comment", fixture.file.path, "Card/Nope", "Hi", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Card/Nope"), "stderr: \(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test("A malformed --at is refused with the form it takes")
    func malformedPoint() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comment", fixture.file.path, "Btn01", "--at", "12", "Hi", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stderr.contains("x,y"), "stderr: \(run.stderr)")
    }

    @Test("A comment needs an author: without --as or $WOODCASE_AS it is refused")
    func needsAuthor() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(["comment", fixture.file.path, "Btn01", "Hi"], environment: ["WOODCASE_AS": ""])

        #expect(run.status == 2)
        #expect(run.stderr.contains("--as"), "stderr: \(run.stderr)")
    }

    @Test("-F reads the text from a file, `-` from standard input")
    func textFromFile() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(
            ["comment", fixture.file.path, "Btn01", "-F", "-", "--id", "CmF", "--as", "ana"],
            stdin: Data("# Heading\n- [ ] a task\n".utf8)
        )

        #expect(run.status == 0, "comment refused: \(run.stderr)")
        guard case let .note(data) = try root("CmF", in: fixture).kind else {
            Issue.record("CmF is not a note")
            return
        }
        #expect(data.content == .literal("# Heading\n- [ ] a task"))
    }

    @Test("Text both inline and from -F is refused")
    func textTwice() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(["comment", fixture.file.path, "Btn01", "Hi", "-F", "-", "--as", "ana"], stdin: Data("x".utf8))

        #expect(run.status == 2)
        #expect(run.stderr.contains("not both"), "stderr: \(run.stderr)")
    }

    @Test("The write is in the activity log under the author's name")
    func activity() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comment", fixture.file.path, "Btn01", "Hi", "--id", "CmLog", "--as", "claude")
        #expect(run.status == 0, "comment refused: \(run.stderr)")

        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        let row = try #require(log.split(separator: "\n").last)
        #expect(row.contains(#""identity":"claude""#), "row: \(row)")
        #expect(row.contains("CmLog"), "row: \(row)")
    }

    @Test("--dry-run writes nothing")
    func dryRun() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let original = try Data(contentsOf: fixture.file)
        let run = try fixture.run("comment", fixture.file.path, "Btn01", "Hi", "--dry-run", "--as", "ana")

        #expect(run.status == 0, "comment refused: \(run.stderr)")
        #expect(run.stdoutLines.first == DryRunOption.marker)
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test("The new thread lists in comments, with its time")
    func listed() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        _ = try fixture.run("comment", fixture.file.path, "Btn01", "--at", "1,2", "Hi @ana", "--id", "CmNew", "--as", "claude")
        let run = try fixture.run("comments", fixture.file.path, "--mentions", "ana")

        let row = try #require(run.stdoutLines.first { $0.hasSuffix("CmNew") })
        #expect(row.hasPrefix("open "))
        #expect(row.contains("Btn01 @1,2"))
        #expect(row.contains(#/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/#), "row: \(row)")
    }
}
