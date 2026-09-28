//
//  PenFileProbe.swift
//  WoodcaseCommandTests
//

import Foundation
import Woodcase

/// Reads back the .pen file a mutating verb has just written, and finds nodes in it
/// by the same name paths the verb was given.
///
/// A verb test asserts three things: what the process printed, what it exited with,
/// and what is now on disk. This is the third — the file parsed through the real
/// parser, so a verb that wrote something the parser cannot read fails here rather
/// than much later.
///
/// ```swift
/// let probe = try PenFileProbe(fixture.file)
/// #expect(probe.node("Canvas/Title")?.textContent == "Hi")
/// ```
struct PenFileProbe {
    /// Parses a .pen file.
    ///
    /// - Parameter url: The file to read.
    /// - Throws: Whatever ``PenParser`` throws for a file it cannot read.
    init(_ url: URL) throws {
        document = try PenParser.parse(contentsOf: url)
    }

    /// The parsed document.
    let document: PenDocument

    /// The document's root nodes, in order.
    var roots: [PenNode] {
        document.children
    }

    /// The node at a name path, walking from the roots.
    ///
    /// - Parameter path: A `/`-separated path of node names, from a root down.
    /// - Returns: The node, or `nil` when no such path exists.
    func node(_ path: String) -> PenNode? {
        var current: [PenNode] = roots
        var found: PenNode?
        for segment in path.split(separator: "/").map(String.init) {
            guard let match = current.first(where: { $0.common.name == segment }) else { return nil }
            found = match
            current = Self.children(of: match)
        }
        return found
    }

    /// A root node by name.
    ///
    /// - Parameter name: The root's `common.name`.
    /// - Returns: The root, or `nil` when no root has that name.
    func root(named name: String) -> PenNode? {
        roots.first { $0.common.name == name }
    }

    /// A node's inline children, whatever kind of container it is.
    ///
    /// - Parameter node: The node to look inside.
    /// - Returns: Its children, empty for a node that cannot hold any.
    static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }
}

extension PenNode {
    /// The literal text of a `text` node, for an assertion that reads like the file.
    var textContent: String? {
        guard case let .text(data) = kind, let content = data.content else { return nil }
        guard case let .literal(value) = content else { return nil }
        return value
    }

    /// A frame's declared width, for an assertion that a typed value survived.
    var frameWidth: PenSizing? {
        guard case let .frame(data) = kind else { return nil }
        return data.width
    }

    /// A frame's fills, for an assertion that a structured value survived the write.
    var frameFills: PenFills? {
        guard case let .frame(data) = kind else { return nil }
        return data.fills
    }

    /// The literal `x` of a node, for an assertion about placement.
    var literalX: Double? {
        Self.literal(common.x)
    }

    /// The literal `y` of a node, for an assertion about placement.
    var literalY: Double? {
        Self.literal(common.y)
    }

    /// The number behind a coordinate, or `nil` when it is absent or a variable.
    private static func literal(_ value: PenValue<Double>?) -> Double? {
        guard let value, case let .literal(number) = value else { return nil }
        return number
    }
}
