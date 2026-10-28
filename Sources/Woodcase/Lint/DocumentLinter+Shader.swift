//
//  DocumentLinter+Shader.swift
//  Woodcase
//

import Foundation

/// The `shader-not-drawn` check.
///
/// Pen runs a shader fill — uniforms, samplers, `@sdf`, `@backdrop`, on shapes, text and
/// icons — and a shader effect over the rendered node (format 2.21), and Woodcase runs
/// neither: not the renderer (so not `render`, `shot` or the viewer), not the React or
/// SwiftUI code. The file is well formed and Pen draws it as written, so the finding is a
/// warning that Woodcase's output will not match Pen's (`render-shader-fills.pen`; finding
/// F1 of `project/2026-09-27-fidelity-gaps.md`). Which shaders count is ``ShaderFills``'
/// rule: an enabled shader, in the fills, the stroke or the effects.
extension DocumentLinter {
    /// One finding per enabled shader on a node: fills first, then the stroke, then effects.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: The findings, in the order the node lists its paints.
    static func shaderFindings(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        ShaderFills.found(in: node.kind).map { shader in
            let consequence = shader.role == .effect
                ? "render, shot and generated code draw the node without it"
                : "render, shot and generated code leave that paint out"
            return finding(
                .shaderNotDrawn, row,
                "has a shader \(shader.label) (`\(shader.url)`) that Pen runs and Woodcase does not draw: "
                    + "\(consequence), so they will not match Pen."
            )
        }
    }
}
