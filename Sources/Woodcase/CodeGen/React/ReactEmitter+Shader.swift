//
//  ReactEmitter+Shader.swift
//  Woodcase
//

extension ReactEmitter {
    /// The warning for a node whose shader fill React drops.
    ///
    /// React writes nothing for a shader, wherever it sits — a background, a text's or an
    /// icon's glyphs, a stroke — since the web target has no shader runtime either, where
    /// Pen runs it (``ShaderFills``). The wording is SwiftUI's own for the same gap.
    static let droppedShaderWarning = "React does not emit shader fills yet"

    /// The warning for a node whose only shader is an effect (format 2.21): React writes
    /// the node unprocessed, as if the effect were absent.
    static let droppedShaderEffectWarning = "React does not emit shader effects yet"

    /// Warns once per node, per file, when `node` has an enabled shader in its fills, its
    /// stroke or its effects; a node with a shader paint gets the fill warning.
    static func warnDroppedShaders(_ node: PenNode, ctx: EmitContext) {
        let found = ShaderFills.found(in: node.kind)
        guard !found.isEmpty, ctx.shaderWarnedNodes.insert(node.id).inserted else { return }
        let message = found.allSatisfy { $0.role == .effect } ? droppedShaderEffectWarning : droppedShaderWarning
        ctx.diagnostics?.warn(message, stage: .codeGen, nodeID: node.id)
    }
}
