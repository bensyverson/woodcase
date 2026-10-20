//
//  FigmaSVGOracle.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Reads the paths of a committed `reference.svg`, Figma's own export of a fixture, so the
/// blob tests can hold decoded geometry against an independent oracle.
///
/// Figma exports absolute commands only (`M`, `L`, `H`, `V`, `C`, `Z`), in the selection
/// root's coordinates, so a direct child's geometry lines up after its own transform's
/// translation. Quadratic curves arrive as cubics; ``matches(_:_:tolerance:)`` elevates the
/// decoded side to compare them.
enum FigmaSVGOracle {
    /// One `<path>` element: its `d` and its other attributes.
    struct Element {
        /// The path data, parsed.
        var commands: [FigmaPathCommand]
        /// Every attribute but `d`, by name.
        var attributes: [String: String]
    }

    /// Every `<path>` in a committed case's `reference.svg`, in document order.
    static func paths(_ caseID: String) throws -> [Element] {
        let url = try #require(Bundle.module.url(
            forResource: "reference", withExtension: "svg", subdirectory: "Fixtures/Figma/\(caseID)"
        ))
        let svg = try String(contentsOf: url, encoding: .utf8)
        return try svg.matches(of: /<path\s([^>]*?)\/?>/).map { match in
            var attributes: [String: String] = [:]
            for attribute in match.1.matches(of: /([a-z-]+)="([^"]*)"/) {
                attributes[String(attribute.1)] = String(attribute.2)
            }
            let pathData = attributes.removeValue(forKey: "d")
            let data = try #require(pathData)
            return try Element(commands: commands(data), attributes: attributes)
        }
    }

    /// Parses absolute SVG path data into path commands, `H` and `V` as lines.
    static func commands(_ data: String) throws -> [FigmaPathCommand] {
        let tokens = data.matches(of: /[MLHVCZ]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?/).map { String($0.output) }
        var commands: [FigmaPathCommand] = []
        var index = 0
        var current = FigmaPoint.zero
        var start = FigmaPoint.zero
        func number() throws -> Double {
            defer { index += 1 }
            return try #require(index < tokens.count ? Double(tokens[index]) : nil, "number at token \(index) of \(data)")
        }
        func point() throws -> FigmaPoint {
            try FigmaPoint(x: number(), y: number())
        }
        var letter = ""
        while index < tokens.count {
            if Double(tokens[index]) == nil {
                letter = tokens[index]
                index += 1
            }
            switch letter {
            case "M":
                current = try point()
                start = current
                commands.append(.move(to: current))
                letter = "L"
            case "L":
                current = try point()
                commands.append(.line(to: current))
            case "H":
                current = try FigmaPoint(x: number(), y: current.y)
                commands.append(.line(to: current))
            case "V":
                current = try FigmaPoint(x: current.x, y: number())
                commands.append(.line(to: current))
            case "C":
                let control1 = try point()
                let control2 = try point()
                current = try point()
                commands.append(.cubic(control1: control1, control2: control2, to: current))
            case "Z":
                current = start
                commands.append(.close)
                letter = ""
            default:
                Issue.record("unsupported path token \(tokens[index]) in \(data)")
                return commands
            }
        }
        return commands
    }

    /// Whether `decoded` draws the same path as `reference` within `tolerance` in every
    /// coordinate, elevating `decoded`'s quadratic curves to the cubics Figma exports.
    static func matches(_ decoded: [FigmaPathCommand], _ reference: [FigmaPathCommand], tolerance: Double = 0.01) -> Bool {
        let elevated = cubic(decoded)
        guard elevated.count == reference.count else { return false }
        return zip(elevated, reference).allSatisfy { lhs, rhs in
            let left = points(lhs)
            let right = points(rhs)
            guard left.count == right.count, kind(lhs) == kind(rhs) else { return false }
            return zip(left, right).allSatisfy { abs($0.x - $1.x) <= tolerance && abs($0.y - $1.y) <= tolerance }
        }
    }

    /// `commands` with every quadratic curve raised to the cubic that draws it.
    static func cubic(_ commands: [FigmaPathCommand]) -> [FigmaPathCommand] {
        var current = FigmaPoint.zero
        var start = FigmaPoint.zero
        return commands.map { command in
            defer {
                switch command {
                case let .move(to):
                    current = to
                    start = to
                case let .line(to), let .quadratic(_, to), let .cubic(_, _, to): current = to
                case .close: current = start
                }
            }
            guard case let .quadratic(control, to) = command else { return command }
            return .cubic(
                control1: FigmaPoint(x: current.x + 2 / 3 * (control.x - current.x), y: current.y + 2 / 3 * (control.y - current.y)),
                control2: FigmaPoint(x: to.x + 2 / 3 * (control.x - to.x), y: to.y + 2 / 3 * (control.y - to.y)),
                to: to
            )
        }
    }

    private static func points(_ command: FigmaPathCommand) -> [FigmaPoint] {
        switch command {
        case let .move(to), let .line(to): [to]
        case let .quadratic(control, to): [control, to]
        case let .cubic(control1, control2, to): [control1, control2, to]
        case .close: []
        }
    }

    private static func kind(_ command: FigmaPathCommand) -> Int {
        switch command {
        case .move: 0
        case .line: 1
        case .quadratic: 2
        case .cubic: 3
        case .close: 4
        }
    }
}
