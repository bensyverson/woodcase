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

    /// Warns once per node, per file, when `node` has an enabled shader in its fills or its
    /// stroke.
    static func warnDroppedShaders(_ node: PenNode, ctx: EmitContext) {
        guard !ShaderFills.found(in: node.kind).isEmpty, ctx.shaderWarnedNodes.insert(node.id).inserted else { return }
        ctx.diagnostics?.warn(droppedShaderWarning, stage: .codeGen, nodeID: node.id)
    }
}
