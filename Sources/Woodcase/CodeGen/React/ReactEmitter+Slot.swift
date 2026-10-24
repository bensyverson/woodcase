//
//  ReactEmitter+Slot.swift
//  Woodcase
//

/// A component's slots in React (``ReactSlot``): the slot frame drawing its prop or its
/// default content, and a call passing an instance's fill as the prop.
extension ReactEmitter {
    /// The steps that draw a slot frame's content at `indent`: the slot's prop, or its
    /// default content when the caller passes none (``ReactSlot``).
    ///
    /// ```tsx
    /// {list === undefined ? (
    ///   <>
    ///     <ItemA />
    ///   </>
    /// ) : list}
    /// ```
    static func slotSteps(
        _ slot: ReactSlot,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        turnedFillSizes: TurnedFillSizes
    ) -> [ReactEmitStep] {
        let pad = String(repeating: " ", count: indent + 2)
        guard !slot.defaultContent.isEmpty else {
            return [.then { ctx.lines.append("\(pad){\(slot.name)}") }]
        }
        ctx.lines.append("\(pad){\(slot.name) === undefined ? (")
        ctx.lines.append("\(pad)  <>")
        var steps = childSteps(
            slot.defaultContent, component: component, indent: indent + 4, ctx: ctx,
            wrapped: slot.layout == .none, parentLayout: slot.layout
        ) { ctx.turnedFillSizes = turnedFillSizes }
        steps.append(.then {
            ctx.lines.append("\(pad)  </>")
            ctx.lines.append("\(pad)) : \(slot.name)}")
        })
        return steps
    }

    /// The steps that pass one slot's fill as its prop: `null` for an empty fill, else the
    /// content in a fragment, drawn in the caller's scope as the slot frame places its
    /// children.
    static func slotFillSteps(
        _ slot: ReactSlot,
        content: [PenNode],
        enclosing: ComponentDefinition,
        indent: Int,
        ctx: EmitContext
    ) -> [ReactEmitStep] {
        let pad = String(repeating: " ", count: indent + 2)
        guard !content.isEmpty else {
            return [.then { ctx.lines.append("\(pad)\(slot.name)={null}") }]
        }
        let savedPlacement = ctx.childPlacement
        let turnedFillSizes = slot.frameData.map(TurnedFillSizes.init(container:)) ?? TurnedFillSizes()
        var steps: [ReactEmitStep] = [.then {
            ctx.lines.append("\(pad)\(slot.name)={")
            ctx.lines.append("\(pad)  <>")
            ctx.childPlacement = slot.layout == .none ? .free : .flow
        }]
        steps += childSteps(
            content, component: enclosing, indent: indent + 4, ctx: ctx,
            wrapped: slot.layout == .none, parentLayout: slot.layout
        ) { ctx.turnedFillSizes = turnedFillSizes }
        steps.append(.then {
            ctx.lines.append("\(pad)  </>")
            ctx.lines.append("\(pad)}")
            ctx.childPlacement = savedPlacement
        })
        return steps
    }
}
