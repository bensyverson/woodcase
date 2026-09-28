//
//  ReactEmitter+StateVars.swift
//  Woodcase
//

extension ReactEmitter {
    /// Replace literal style values with CSS variable references for state-affected properties.
    ///
    /// Only designer-override states use `var()` substitution — smart defaults are additive
    /// CSS and don't need to replace inline values. A state that turns or flips the node
    /// gets its `transform` even when the node itself has none, turning about `pivot`.
    static func substituteStateVars(
        _ styles: inout [(String, String)],
        pivot: TransformPivot,
        ctx: EmitContext
    ) {
        guard !ctx.stateAffectedProps.isEmpty,
              let className = ctx.stateClassName,
              let affected = ctx.stateAffectedProps[ctx.currentNodePath]
        else { return }

        // CSS style key → DeltaProperty mapping
        let keyToDelta: [String: DeltaProperty] = [
            "backgroundColor": .fills,
            "background": .fills,
            "borderRadius": .cornerRadius,
            "opacity": .opacity,
            "color": .textColor,
            "fontSize": .fontSize,
            "fontWeight": .fontWeight,
            "width": .width,
            "height": .height,
            "padding": .padding,
            "gap": .gap,
            "transform": .transform,
        ]

        for i in styles.indices {
            let (key, _) = styles[i]
            if let delta = keyToDelta[key], affected.contains(delta) {
                let varName = StateEmitter.cssVarName(
                    className: className, nodePath: ctx.currentNodePath, property: delta
                )
                styles[i] = (key, "\"var(\(varName))\"")
            }
        }

        if affected.contains(.transform), !styles.contains(where: { $0.0 == "transform" }) {
            let varName = StateEmitter.cssVarName(className: className, nodePath: ctx.currentNodePath, property: .transform)
            styles.append(("transform", "\"var(\(varName))\""))
            if let origin = pivot.transformOrigin {
                styles.append(("transformOrigin", "\"\(origin)\""))
            }
        }
    }
}
