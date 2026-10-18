//
//  SwiftUIViewRequest.swift
//  Woodcase
//

/// A node whose view a ``SwiftUIPendingView`` waits on, and the emitter that draws it.
///
/// The emitter travels with the node because it is not always the asker's: an inlined
/// instance draws its copy with the scope of the component it came from.
struct SwiftUIViewRequest {
    /// The emitter that draws the node.
    var emitter: SwiftUINodeEmitter

    /// The node.
    var node: PenNode

    /// What the node sits in.
    var container: SwiftUINodeEmitter.Container
}
