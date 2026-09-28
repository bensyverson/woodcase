//
//  DocumentLinterMeshPointTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A mesh point written in neither wire form (``PenMeshPoint/malformed(_:)``), through
/// `mesh-gradient-dropped` and `mesh-gradient-distorted`.
///
/// One Pen cannot place leaves the whole fill unpainted, so it is dropped (an error); one
/// Pen places anyway — at its grid position, or at the first two numbers of a longer
/// array — is painted, but not from what the file says, so it is distorted (a warning).
/// Pen's behaviour: `project/2026-09-26-what-pen-drops-from-a-file.md`.
@MainActor
struct DocumentLinterMeshPointTests {
    private static let colors = ##"["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#00FFFF", "#FF00FF"]"##

    /// A document whose one frame carries a 3×2 mesh with vertex 2 written as `point`.
    private func board(point: String) throws -> EditableDocument {
        let json = """
        {"version": "2.17", "children": [
          {"type": "frame", "id": "Msh01", "name": "Mesh", "x": 0, "y": 0, "width": 150, "height": 100,
           "fill": {"type": "mesh_gradient", "columns": 3, "rows": 2, "colors": \(Self.colors),
                    "points": [[0,0], \(point), [1,0], [0,1], [0.5,1], [1,1]]}}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(json))
    }

    private func meshFindings(_ point: String) throws -> [LintFinding] {
        try DocumentLinter.findings(in: board(point: point)).filter {
            $0.check == .meshGradientDropped || $0.check == .meshGradientDistorted
        }
    }

    @Test("A point Pen cannot place is a dropped fill naming the vertex and what it holds")
    func unplaceableIsDropped() throws {
        let found = try meshFindings("[1]")
        #expect(found.map(\.check) == [.meshGradientDropped])
        let message = try #require(found.first?.message)
        #expect(message.contains("vertex 2"))
        #expect(message.contains("`[1]`"))
        #expect(message.contains("paints nothing"))
    }

    @Test("An unplaceable handle is a dropped fill too")
    func unplaceableHandleIsDropped() throws {
        let found = try meshFindings(##"{"position":[0.5,0],"leftHandle":"oops"}"##)
        #expect(found.map(\.check) == [.meshGradientDropped])
    }

    @Test("A point Pen places at its grid position is distorted, naming where Pen puts it")
    func repairedIsDistorted() throws {
        let found = try meshFindings(##""oops""##)
        #expect(found.map(\.check) == [.meshGradientDistorted])
        let message = try #require(found.first?.message)
        #expect(message.contains("vertex 2"))
        #expect(message.contains(##"`"oops"`"##))
        #expect(message.contains("`[0.5,0]`"))
    }

    @Test("A longer array is distorted, naming the two numbers Pen reads")
    func longArrayIsDistorted() throws {
        let found = try meshFindings("[0.3,0.2,9]")
        #expect(found.map(\.check) == [.meshGradientDistorted])
        #expect(try #require(found.first?.message).contains("`[0.3,0.2]`"))
    }

    @Test("A repaired point object keeps the handles Pen reads in the suggestion")
    func repairedObjectSuggestsObject() throws {
        let found = try meshFindings(##"{"leftHandle":[-0.3,0.2]}"##)
        #expect(found.map(\.check) == [.meshGradientDistorted])
        #expect(try #require(found.first?.message).contains(##"`{"leftHandle":[-0.3,0.2],"position":[0.5,0]}`"##))
    }

    @Test("A well-formed 3×2 mesh has no mesh finding")
    func wellFormedIsClean() throws {
        #expect(try meshFindings("[0.5,0]").isEmpty)
    }
}
