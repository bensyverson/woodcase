//
//  ChildPlacement.swift
//  Woodcase
//

/// How a container places a child React emits inside it: the one fact that a child's
/// transform pivot and its `fill_container` sizing both follow.
enum ChildPlacement: Friendly {
    /// In a flex flow: the container's layout sizes and positions the child. A component's
    /// or page's root counts as flowed, placed by whatever renders it.
    case flow
    /// By the child's own `x`/`y`: a child of a `layout: "none"` frame or of a group, or
    /// one positioned absolutely. Pen gives such a child no container size to fill, so a
    /// `fill_container(N)` side takes its fallback `N`.
    case free

    /// The pivot a child placed this way turns and flips about (see ``TransformPivot``).
    var pivot: TransformPivot {
        switch self {
        case .flow: .center
        case .free: .anchor
        }
    }
}
