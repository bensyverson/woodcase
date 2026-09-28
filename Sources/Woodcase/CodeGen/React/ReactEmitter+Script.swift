//
//  ReactEmitter+Script.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Script Node Emission

    /// Emits an empty placeholder `<div>` for a `script` node.
    ///
    /// Scripts are never executed by the code generator — only the node's
    /// declared size is preserved, with a comment naming the script so the
    /// generated source documents what was skipped.
    static func emitScript(
        _ node: PenNode,
        data: PenNode.ScriptData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)
        let label = data.scriptUri ?? node.common.name ?? node.id
        ctx.lines.append("\(pad){/* script \"\(label)\" is not executed */}")

        var styles: [(String, String)] = []
        let placement = ctx.placement(for: node.common)
        if let width = data.width, let cssWidth = emitSizing(width, placement: placement, fitsContent: false) {
            styles.append(("width", cssWidth))
        }
        if let height = data.height, let cssHeight = emitSizing(height, placement: placement, fitsContent: false) {
            styles.append(("height", cssHeight))
        }
        styles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        styles.append(contentsOf: emitCommonStyles(node.common, blendMode: nil, pivot: ctx.transformPivot(for: node.common)))

        ctx.lines.append("\(pad)<div")
        ctx.lines.append("\(pad)  style={{")
        for (key, value) in styles {
            ctx.lines.append("\(pad)    \(key): \(value),")
        }
        ctx.lines.append("\(pad)  }}")
        ctx.lines.append("\(pad)/>")
    }
}
