//
//  FigmaPathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaPath(blob:)` reads a command stream — a glyph's `commandsBlob` or a `Path`'s —
/// one opcode byte and its float arguments at a time.
struct FigmaPathTests {
    private typealias Bytes = FigmaBlobBytes

    private static func point(_ x: Double, _ y: Double) -> FigmaPoint {
        FigmaPoint(x: x, y: y)
    }

    @Test("Each opcode reads its own number of coordinates")
    func everyCommand() throws {
        let blob = Bytes.commands([
            (1, [0.5, 0.25]),
            (2, [1, 0]),
            (3, [1.5, 0.5, 1, 1]),
            (4, [0.75, 1.25, 0.25, 1.25, 0, 1]),
            (0, []),
        ])
        #expect(try FigmaPath(blob: blob).commands == [
            .move(to: Self.point(0.5, 0.25)),
            .line(to: Self.point(1, 0)),
            .quadratic(control: Self.point(1.5, 0.5), to: Self.point(1, 1)),
            .cubic(control1: Self.point(0.75, 1.25), control2: Self.point(0.25, 1.25), to: Self.point(0, 1)),
            .close,
        ])
    }

    @Test("A glyph stream's leading close, before any subpath, is dropped")
    func leadingClose() throws {
        let blob = Bytes.commands([(0, []), (1, [0, 0]), (2, [1, 0]), (0, []), (0, [])])
        #expect(try FigmaPath(blob: blob).commands == [
            .move(to: Self.point(0, 0)),
            .line(to: Self.point(1, 0)),
            .close,
        ])
    }

    @Test("A glyph with no outline, such as a space, is one zero byte and decodes to nothing")
    func blankGlyph() throws {
        #expect(try FigmaPath(blob: Data([0])).commands.isEmpty)
        #expect(try FigmaPath(blob: Data()).commands.isEmpty)
    }

    @Test("An opcode outside 0 through 4 is refused at its offset")
    func unknownOpcode() throws {
        let blob = Bytes.commands([(1, [0, 0]), (9, [])])
        #expect(throws: FigmaBlobError.unknownCommand(9, offset: 9)) {
            try FigmaPath(blob: blob)
        }
    }

    @Test("A command cut short of its coordinates is refused")
    func truncatedArguments() throws {
        let blob = Bytes.commands([(4, [1, 2, 3, 4, 5, 6])])
        for length in 1 ..< blob.count {
            #expect(throws: FigmaBlobError.self) {
                try FigmaPath(blob: blob.prefix(length))
            }
        }
    }

    @Test("A coordinate that is not finite is refused")
    func nonFinite() throws {
        let blob = Bytes.commands([(1, [0, .nan])])
        #expect(throws: FigmaBlobError.nonFiniteValue(offset: 5)) {
            try FigmaPath(blob: blob)
        }
    }

    @Test("Mapping a path moves every point and keeps every command")
    func mapped() {
        let path = FigmaPath(commands: [
            .move(to: Self.point(1, 1)),
            .quadratic(control: Self.point(2, 0), to: Self.point(3, 1)),
            .close,
        ])
        let moved = path.mapped { FigmaPoint(x: $0.x * 10, y: -$0.y) }
        #expect(moved.commands == [
            .move(to: Self.point(10, -1)),
            .quadratic(control: Self.point(20, 0), to: Self.point(30, -1)),
            .close,
        ])
    }
}
