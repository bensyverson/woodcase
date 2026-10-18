//
//  ReactEmitStep.swift
//  Woodcase
//

/// One piece of work left in a React emission, on the work list
/// ``ReactEmitter/emitNode(_:component:indent:ctx:isRoot:parentLayout:)`` drains.
///
/// React's markup is written in document order into the file's ``EmitContext``: a
/// container writes its opening lines, then each child, then its closing lines, and sets
/// what its children read from the context — how it places them, their node path, the
/// boxes it fixes for them — around each one. Rather than calling itself for each child,
/// a container hands back the steps that remain, in order: a ``node(_:component:indent:isRoot:parentLayout:)``
/// per child, and ``then(_:)`` for whatever its recursive form did between and after the
/// calls. The driver runs them depth first, so the lines and the context changes happen
/// in the order they always did, and the stack no longer grows with the tree (issue
/// `g5SACU`).
///
/// It is not `Friendly`: a ``then(_:)`` step holds a closure over the context.
enum ReactEmitStep {
    /// Emit a node and everything under it.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - component: The component (or a page's stand-in) whose markup it is part of.
    ///   - indent: Its indentation, in spaces.
    ///   - isRoot: Whether it is the file's root element.
    ///   - parentLayout: The layout of the container it sits in.
    case node(PenNode, component: ComponentDefinition, indent: Int, isRoot: Bool, parentLayout: PenLayoutDirection?)

    /// Run `work` — write a closing line, restore what a container set for its children —
    /// once every step before it has run.
    case then(() -> Void)
}
