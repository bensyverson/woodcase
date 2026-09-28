//
//  DocumentLinter+Shader.swift
//  Woodcase
//

import Foundation

/// The `shader-not-drawn` check.
///
/// Pen runs a shader fill — uniforms, samplers, `@sdf`, `@backdrop`, on shapes, text and
/// icons — and Woodcase draws nothing for one: not the renderer (so not `render`, `shot`
/// or the viewer), not the React or SwiftUI code. The file is well formed and Pen draws it
/// as written, so the finding is a warning that Woodcase's output will not match Pen's
/// (`render-shader-fills.pen`; finding F1 of `project/2026-09-27-fidelity-gaps.md`). Which
/// fills count is ``ShaderFills``' rule: an enabled shader, in the fills or the stroke.
extension DocumentLinter {
    /// One finding per enabled shader on a node, fills first, then the stroke.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: The findings, in the order the node lists its paints.
    static func shaderFindings(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        ShaderFills.found(in: node.kind).map { shader in
            finding(
                .shaderNotDrawn, row,
                "has a shader \(shader.label) (`\(shader.url)`) that Pen runs and Woodcase does not draw: "
                    + "render, shot and generated code leave that paint out, so they will not match Pen."
            )
        }
    }
}
