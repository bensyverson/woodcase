//
//  TreeDeepNestingTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `woodcase tree` on documents nested deeper than any test fixture.
///
/// The verb parses, expands, resolves and lays out the document inside a Swift task,
/// whose thread has 512 KiB of stack, and a debug build gives every value temporary its
/// own slot. Every stage used to walk the tree recursively: a frame tree thirty-five
/// deep, or sixteen nested instances, killed the process with SIGBUS — exit 138, no
/// output. Every walk the verb makes now runs from a work list, so these depths are far
/// past where it used to fail rather than just inside it. The tests drive the debug
/// binary in a child process, so an overflow fails one test instead of taking the
/// suite down; the stack each stage uses is measured in-process by
/// `TreePipelineStackTests`, and the history is in
/// `project/2026-09-26-debug-stack-depth.md`.
struct TreeDeepNestingTests {
    /// Instances nested inside one another, each component placing the one before it.
    private static let instanceDepth = 32

    /// Plain frames wrapping each component's nested instance.
    private static let framesPerComponent = 1

    /// Frames nested inside one another in a plain root.
    ///
    /// JSON nesting caps a parsed frame tree at about 255 levels (Foundation refuses
    /// input nested past 512 arrays and objects), so this is near the deepest a file can
    /// be.
    private static let frameTreeDepth = 200

    @Test("Thirty-two nested instances list with --expand")
    func deepInstanceNestingLists() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let file = try Self.write(Self.nestedInstances(), named: "nested.pen", in: fixture)

        let run = try fixture.run("tree", file.path, "Top", "--expand")

        #expect(run.status == 0, "stderr: \(run.stderr)")
        // The innermost instance's leaf is reached, and the top instance's bare key
        // renamed the slot content the outermost component wrote.
        #expect(run.stdout.contains("/Leaf"))
        #expect(run.stdout.contains("patched"))
    }

    @Test("A frame tree two hundred levels deep lists")
    func deepFrameTreeLists() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let file = try Self.write(Self.frameTree(), named: "frames.pen", in: fixture)

        let run = try fixture.run("tree", file.path)

        #expect(run.status == 0, "stderr: \(run.stderr)")
        #expect(run.stdout.contains("D\(Self.frameTreeDepth - 1)"))
    }

    // MARK: - Fixtures

    /// Writes a generated document beside the fixture's own file.
    private static func write(_ json: String, named name: String, in fixture: CommandFixture) throws -> URL {
        let url = fixture.root.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    /// `C0` is a leaf; each `C<i>` wraps an instance of `C<i-1>` in frames and writes a
    /// rectangle into its slot. `Top` places the last one and renames that rectangle.
    private static func nestedInstances() -> String {
        var components: [String] = [
            #"{"id": "C0", "type": "frame", "reusable": true, "children": ["#
                + #"{"id": "Hole0", "type": "frame", "children": []},"#
                + #"{"id": "Leaf", "type": "rectangle", "width": 4, "height": 4}]}"#,
        ]
        for level in 1 ..< instanceDepth {
            let instance = #"{"id": "I\#(level)", "type": "ref", "ref": "C\#(level - 1)", "descendants": {"#
                + #""Hole\#(level - 1)": {"children": [{"id": "Inj\#(level)", "type": "rectangle", "width": 2}]}}}"#
            var wrapped = instance
            for frame in 0 ..< framesPerComponent {
                wrapped = #"{"id": "F\#(level)x\#(frame)", "type": "frame", "children": [\#(wrapped)]}"#
            }
            components.append(
                #"{"id": "C\#(level)", "type": "frame", "reusable": true, "children": ["#
                    + #"{"id": "Hole\#(level)", "type": "frame", "children": []}, \#(wrapped)]}"#
            )
        }
        let top = #"{"id": "Top", "type": "ref", "ref": "C\#(instanceDepth - 1)", "descendants": {"#
            + #""Inj\#(instanceDepth - 1)": {"name": "patched"}}}"#
        return #"{"version": "2.17", "children": [\#(components.joined(separator: ", ")), \#(top)]}"#
    }

    /// One root frame with `frameTreeDepth - 1` frames nested below it.
    private static func frameTree() -> String {
        var tree = #"{"id": "D\#(frameTreeDepth - 1)", "type": "frame"}"#
        for level in stride(from: frameTreeDepth - 2, through: 0, by: -1) {
            tree = #"{"id": "D\#(level)", "type": "frame", "children": [\#(tree)]}"#
        }
        return #"{"version": "2.17", "children": [\#(tree)]}"#
    }
}
