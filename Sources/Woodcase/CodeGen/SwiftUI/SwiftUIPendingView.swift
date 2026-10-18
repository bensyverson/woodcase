//
//  SwiftUIPendingView.swift
//  Woodcase
//

/// A value the SwiftUI node emitter is still working out: known now, or waiting on the
/// views of some nodes below.
///
/// A SwiftUI view is built from its children's views — a frame's stack holds them, an
/// instance's call passes them to its slots — so the emitter used to call itself for each
/// child, one call per level of the tree, and a deep design overflowed a Swift task's
/// stack (issue `g5SACU`). Now a node's emitter does what it can before its children, then
/// returns ``awaiting(_:then:)`` with requests for their views and a continuation that
/// finishes from them. ``SwiftUINodeEmitter/view(for:in:)`` drains these from a work list,
/// one request at a time and depth first — the order the recursion drew in — so each
/// emitter's side effects (the theme reads it marks and rolls back, the shapes it
/// declares, the warnings it gives) come in the same order, and the stack stays flat.
///
/// ``map(_:)`` and ``flatMap(_:)`` chain the steps of one node's work; how deep that chain
/// goes depends on the emitter's code, never on the tree. It is not `Friendly`: it holds
/// closures.
enum SwiftUIPendingView<Value> {
    /// The value, known.
    case done(Value)

    /// Waiting on `requests`' views — each `nil` when its node is switched off — in order,
    /// to finish with `then`.
    case awaiting(_ requests: [SwiftUIViewRequest], then: ([SwiftUIViewCode?]) -> SwiftUIPendingView<Value>)

    /// The value, once known, transformed by `transform`.
    func map<Mapped>(_ transform: @escaping (Value) -> Mapped) -> SwiftUIPendingView<Mapped> {
        flatMap { .done(transform($0)) }
    }

    /// The value, once known, handed to `next`, which may wait on more views.
    func flatMap<Mapped>(_ next: @escaping (Value) -> SwiftUIPendingView<Mapped>) -> SwiftUIPendingView<Mapped> {
        switch self {
        case let .done(value):
            next(value)
        case let .awaiting(requests, then):
            .awaiting(requests) { then($0).flatMap(next) }
        }
    }
}
