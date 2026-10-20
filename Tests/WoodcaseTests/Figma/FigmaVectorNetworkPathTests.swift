//
//  FigmaVectorNetworkPathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A vector network's regions and segments become path commands: loops walk their
/// segments end to end, tangents become cubic control points, and a loop that returns to
/// its first vertex closes.
struct FigmaVectorNetworkPathTests {
    private typealias Bytes = FigmaBlobBytes

    private static func point(_ x: Double, _ y: Double) -> FigmaPoint {
        FigmaPoint(x: x, y: y)
    }

    @Test("A closed straight loop moves, draws a line per segment and closes")
    func closedTriangle() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(1, 0, 80), (1, 40, 0), (1, 80, 80)],
            segments: [Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(2, 0)],
            regions: [(1, [[0, 1, 2]])]
        ))
        #expect(try network.path(ofRegion: 0).commands == [
            .move(to: Self.point(0, 80)),
            .line(to: Self.point(40, 0)),
            .line(to: Self.point(80, 80)),
            .line(to: Self.point(0, 80)),
            .close,
        ])
    }

    @Test("A curved segment's control points are its vertices plus their tangents")
    func cubicControls() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(0, 0, 22.5), (0, 60, 22.5)],
            segments: [(0, 0, 20, -30, 1, -20, -30)],
            regions: [(1, [[0]])]
        ))
        #expect(try network.path(ofRegion: 0).commands == [
            .move(to: Self.point(0, 22.5)),
            .cubic(control1: Self.point(20, -7.5), control2: Self.point(40, -7.5), to: Self.point(60, 22.5)),
        ])
    }

    @Test("A segment stored backwards in a loop is walked from its end, with its tangents swapped")
    func reversedSegment() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(0, 0, 0), (0, 10, 0), (0, 10, 10)],
            segments: [(0, 1, 0, 0, 0, 0, 0), (0, 2, 1, 2, 1, 3, 4), Bytes.line(2, 0)],
            regions: [(1, [[0, 1, 2]])]
        ))
        #expect(try network.path(ofRegion: 0).commands == [
            .move(to: Self.point(0, 0)),
            .line(to: Self.point(10, 0)),
            .cubic(control1: Self.point(13, 4), control2: Self.point(11, 12), to: Self.point(10, 10)),
            .line(to: Self.point(0, 0)),
            .close,
        ])
    }

    @Test("A loop that does not return to its first vertex stays open")
    func openLoop() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(3, 0, 40), (3, 20, 0), (3, 40, 40)],
            segments: [Bytes.line(0, 1), Bytes.line(1, 2)],
            regions: [(1, [[0, 1]])]
        ))
        #expect(try network.path(ofRegion: 0).commands == [
            .move(to: Self.point(0, 40)),
            .line(to: Self.point(20, 0)),
            .line(to: Self.point(40, 40)),
        ])
    }

    @Test("Each loop of a region is its own subpath, so a hole follows its outline")
    func hole() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(0, 0, 0), (0, 4, 0), (0, 4, 4), (0, 1, 1), (0, 2, 1), (0, 2, 2)],
            segments: [
                Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(2, 0),
                Bytes.line(3, 4), Bytes.line(4, 5), Bytes.line(5, 3),
            ],
            regions: [(0, [[0, 1, 2], [3, 4, 5]])]
        ))
        let path = try network.path(ofRegion: 0)
        #expect(path.commands.count == 10)
        #expect(path.commands[5] == .move(to: Self.point(1, 1)))
        #expect(path.commands.last == .close)
    }

    @Test("A loop whose segments do not meet is refused")
    func disconnected() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(0, 0, 0), (0, 1, 0), (0, 5, 5), (0, 6, 5)],
            segments: [Bytes.line(0, 1), Bytes.line(2, 3)],
            regions: [(1, [[0, 1]])]
        ))
        #expect(throws: FigmaBlobError.disconnectedLoop(region: 0, loop: 0, segment: 1)) {
            try network.path(ofRegion: 0)
        }
    }

    @Test("The segment path draws every segment, chaining those that meet")
    func segmentPath() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(
            vertices: [(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 5, 5), (0, 6, 5)],
            segments: [Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(4, 3)]
        ))
        #expect(network.segmentPath().commands == [
            .move(to: Self.point(0, 0)),
            .line(to: Self.point(1, 0)),
            .line(to: Self.point(1, 1)),
            .move(to: Self.point(6, 5)),
            .line(to: Self.point(5, 5)),
        ])
    }

    @Test("A network built from parts refuses indices past its vertices or segments")
    func validatedParts() throws {
        let vertex = FigmaVectorNetwork.Vertex(styleID: 0, position: .zero)
        let segment = FigmaVectorNetwork.Segment(styleID: 0, start: 0, tangentStart: .zero, end: 1, tangentEnd: .zero)
        #expect(throws: FigmaBlobError.vertexIndexOutOfRange(segment: 0, vertex: 1)) {
            try FigmaVectorNetwork(vertices: [vertex], segments: [segment], regions: [])
        }
        let region = FigmaVectorNetwork.Region(styleID: 0, windingRule: .nonzero, loops: [[0, 3]])
        #expect(throws: FigmaBlobError.segmentIndexOutOfRange(region: 0, segment: 3)) {
            try FigmaVectorNetwork(vertices: [vertex, vertex], segments: [segment], regions: [region])
        }
    }
}
