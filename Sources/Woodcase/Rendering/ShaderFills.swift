//
//  ShaderFills.swift
//  Woodcase
//

import Foundation

/// Shader fills: Pen runs them, and Woodcase draws nothing for one on any target.
///
/// A shader fill (``PenFill/PenShaderFill``) is a WebGL fragment shader Pen runs over the
/// node's box — in its editor and in its exporter, on shapes, text and icons alike
/// (`render-shader-fills.pen`; finding F1 of `project/2026-09-27-fidelity-gaps.md`).
/// Woodcase has no shader runtime: the renderer draws such a fill as transparent, and
/// neither code generator writes it. Every place that leaves one out says so from here, so
/// they agree on which fills count: an enabled shader, in a node's fills or its stroke. A
/// disabled one draws nothing in Pen either, and is not reported.
public enum ShaderFills {
    /// One enabled shader fill on a node.
    struct Found: Friendly {
        /// Whether a paint is one of the node's fills or its stroke's paint.
        enum Role: String, Friendly {
            /// One of the node's fills.
            case fill
            /// The stroke's paint.
            case stroke
        }

        /// Which of the node's paint lists holds the shader.
        var role: Role
        /// Its 1-based place in that list.
        var ordinal: Int
        /// How many paints the list holds.
        var total: Int
        /// The shader file, as the fill names it.
        var url: String

        /// The shader's place, as a message names it: `fill`, or `fill 2 of 3` in a stack.
        var label: String {
            total > 1 ? "\(role.rawValue) \(ordinal) of \(total)" : role.rawValue
        }
    }

    /// How many nodes ``diagnostic(under:)`` names before it counts the rest.
    static let namedLimit = 8

    /// Every enabled shader on a node of `kind`, fills first, then the stroke.
    static func found(in kind: PenNode.Kind) -> [Found] {
        let lists = kind.paintLists
        return found(in: lists.fills, role: .fill) + found(in: lists.stroke, role: .stroke)
    }

    /// The one warning a render of `roots` earns for its shader fills, or `nil` when no
    /// node under them has an enabled one.
    ///
    /// The warning names each node that has one — by name and id, in document order, the
    /// first ``namedLimit`` of them — so a caller can find it, and points at `woodcase lint`,
    /// which lists every shader separately. `render` and `shot` print it once per document.
    ///
    /// - Parameter roots: The trees that are drawn: a document's children, or one node.
    /// - Returns: A ``PenDiagnostic/Severity/warning`` at ``PenDiagnostic/Stage/rendering``.
    public static func diagnostic(under roots: [PenNode]) -> PenDiagnostic? {
        let nodes = nodes(under: roots)
        guard let first = nodes.first else { return nil }
        var named = nodes.prefix(namedLimit).map { node in
            "\(node.common.name ?? node.id) (\(node.id))"
        }.joined(separator: ", ")
        if nodes.count > namedLimit {
            named += ", and \(nodes.count - namedLimit) more"
        }
        let count = nodes.count == 1 ? "1 node" : "\(nodes.count) nodes"
        return PenDiagnostic(
            severity: .warning,
            stage: .rendering,
            message: "Woodcase does not draw shader fills, which Pen runs, so \(count) render without that paint: "
                + "\(named). `woodcase lint` lists each one (shader-not-drawn).",
            nodeID: nodes.count == 1 ? first.id : nil
        )
    }

    /// The one warning a shot of the node `id` earns: ``diagnostic(under:)`` for that node
    /// and everything under it, so a shot says nothing of a shader it does not draw.
    ///
    /// - Parameters:
    ///   - document: The document the shot draws from.
    ///   - id: The node the shot draws.
    /// - Returns: The warning, or `nil` when the node has no shader under it or is not there.
    public static func diagnostic(in document: PenDocument, node id: String) -> PenDiagnostic? {
        PenLayoutEngine.node(id: id, in: document.children).flatMap { diagnostic(under: [$0]) }
    }

    /// Every node under `roots`, in document order, that has an enabled shader.
    ///
    /// The walk keeps its pending nodes on the heap: a recursive walk over deep trees
    /// overflows a Swift task's stack (`project/2026-09-26-debug-stack-depth.md`).
    private static func nodes(under roots: [PenNode]) -> [PenNode] {
        var pending = Array(roots.reversed())
        var shaded: [PenNode] = []
        while let node = pending.popLast() {
            if !found(in: node.kind).isEmpty {
                shaded.append(node)
            }
            pending.append(contentsOf: (node.kind.inlineChildrenIfPresent ?? []).reversed())
        }
        return shaded
    }

    /// The enabled shaders in one paint list, numbered by their place in it.
    private static func found(in fills: PenFills?, role: Found.Role) -> [Found] {
        let all = fills?.all ?? []
        return all.enumerated().compactMap { index, fill in
            guard case let .shader(shader) = fill, fill.isEnabled else { return nil }
            return Found(role: role, ordinal: index + 1, total: all.count, url: shader.url)
        }
    }
}
