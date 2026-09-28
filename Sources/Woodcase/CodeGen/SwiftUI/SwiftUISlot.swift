//
//  SwiftUISlot.swift
//  Woodcase
//

/// One slot of a generated component: a frame the designer marked `slot`, which a caller
/// fills with views of its own.
///
/// The view struct takes one generic parameter per slot — `Card<Content: View>` — and a
/// `@ViewBuilder` init parameter that builds it, and the slot frame's stack draws that
/// content where Pen draws the frame's children. The frame's own children are the slot's
/// default content, a view of its own (``defaultTypeName``) that a constrained init
/// passes, so `Card()` still draws what Pen draws; a slot with no children defaults to
/// `EmptyView`.
struct SwiftUISlot: Friendly {
    /// The slot frame, in the component's own tree.
    var frame: PenNode

    /// The `/`-separated run of child names from the component's root to the frame, which
    /// finds the frame again in a state's face (``ComponentAnalyzer/resolveDescendantPath(_:from:)``).
    var path: String

    /// The init parameter and stored property: `content`, `header`.
    var name: String

    /// The generic parameter: `Content`, `HeaderContent`.
    var genericName: String

    /// The view that draws the frame's own children — `CardContentDefault` — or `nil` when
    /// it has none and the default is `EmptyView`.
    var defaultTypeName: String?

    /// The type the slot takes when no caller fills it.
    var defaultType: String {
        defaultTypeName ?? "EmptyView"
    }

    /// The expression that builds the default content: `CardContentDefault()`.
    var defaultCall: String {
        "\(defaultType)()"
    }

    /// The frame's children: the default content.
    var defaultContent: [PenNode] {
        ComponentAnalyzer.childNodes(of: frame)
    }

    /// The frame's layout, which places the content a caller passes.
    var layout: PenLayoutDirection {
        if case let .frame(data) = frame.kind { data.layout ?? .horizontal } else { .none }
    }

    /// What the content's views sit in: the slot frame's stack.
    var container: SwiftUINodeEmitter.Container {
        switch layout {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .none: .absolute
        }
    }

    /// Whether `children` can be the slot's content as views of one builder: in a stack,
    /// a child placed absolutely rides in the frame's overlay, which content cannot reach.
    func holds(_ children: [PenNode]) -> Bool {
        layout == .none || !children.contains { $0.common.layoutPosition == .absolute }
    }

    /// The init's parameter: `@ViewBuilder content: () -> Content`.
    var parameter: String {
        "@ViewBuilder \(name): () -> \(genericName)"
    }

    /// The stored property's declaration, indented.
    var declaration: String {
        "    private let \(name): \(genericName)"
    }

    /// The init's statement that builds the content, indented.
    var assignment: String {
        "        self.\(name) = \(name)()"
    }
}
