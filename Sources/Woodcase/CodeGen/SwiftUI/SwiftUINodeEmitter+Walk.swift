//
//  SwiftUINodeEmitter+Walk.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A node waiting on its children's views, on the walk's work list.
    private struct Waiting {
        /// The views it asked for.
        var requests: [SwiftUIViewRequest]

        /// The views drawn so far, in the order asked.
        var views: [SwiftUIViewCode?]

        /// What finishes the node from all of them.
        var then: ([SwiftUIViewCode?]) -> SwiftUIPendingView<SwiftUIViewCode?>
    }

    /// The view for `node`, or `nil` when the node is switched off (`enabled: false`); a
    /// context node's view is set in its theme (``themed(_:_:since:)``).
    ///
    /// Each node's own emitter (``pendingView(for:in:)``) returns its view or what it waits
    /// on; this drains the waits from a work list, depth first and in order, so the tree is
    /// drawn in the order the recursion drew it and a deep tree costs no more stack than a
    /// shallow one.
    func view(for node: PenNode, in container: Container) -> SwiftUIViewCode? {
        var waiting: [Waiting] = []
        var current = pendingView(for: node, in: container)
        while true {
            switch current {
            case let .done(view):
                guard var parent = waiting.popLast() else { return view }
                parent.views.append(view)
                if parent.views.count < parent.requests.count {
                    let next = parent.requests[parent.views.count]
                    waiting.append(parent)
                    current = next.emitter.pendingView(for: next.node, in: next.container)
                } else {
                    current = parent.then(parent.views)
                }
            case let .awaiting(requests, then):
                guard let first = requests.first else {
                    current = then([])
                    continue
                }
                waiting.append(Waiting(requests: requests, views: [], then: then))
                current = first.emitter.pendingView(for: first.node, in: first.container)
            }
        }
    }

    /// The views of `requests`, in order, once drawn.
    func views(_ requests: [SwiftUIViewRequest]) -> SwiftUIPendingView<[SwiftUIViewCode?]> {
        .awaiting(requests) { .done($0) }
    }

    /// A request for `node`'s view, in `container`, drawn by this emitter.
    func request(for node: PenNode, in container: Container) -> SwiftUIViewRequest {
        SwiftUIViewRequest(emitter: self, node: node, container: container)
    }
}
