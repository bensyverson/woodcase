//
//  SwiftUINodeEmitter+ContentSilhouette.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The silhouette a frame's or a group's outer shadows are cast by: the node itself, laid
    /// out as it is drawn, with every paint replaced by opaque black (``inked(_:)``) — or
    /// `nil` when nothing in it paints (``castsAnything(_:)``).
    ///
    /// Pen CLI 0.3.13 casts a container's outer shadow from its rendered content, as the
    /// renderer's `PenShadowSilhouette` does: its own paint united with its descendants',
    /// clipped where a frame clips, cast as one mask (`render-content-shadows.pen`,
    /// `render-group-shadows.pen`). SwiftUI has no way to read a view's coverage apart from
    /// its alpha, which counts a translucent paint as partial and a child's own shadow as
    /// content, so the page writes the inked copy out and `penContentShadows` casts it as
    /// one composited layer. It is drawn by an emitter that reports nothing
    /// (``silhouetteEmitter``), so the copy's warnings are not reported twice.
    ///
    /// - Parameters:
    ///   - node: A frame or a group.
    ///   - container: What it sits in, which decides how its size is written.
    ///   - flow: How a group sits in a stack, or `nil` when it is placed by its `x`/`y`.
    func contentSilhouette(
        of node: PenNode, in container: Container, flow: GroupFlow? = nil
    ) -> SwiftUIPendingView<SwiftUIViewCode?> {
        guard Self.castsAnything(node) else { return .done(nil) }
        let inked = Self.inked(node)
        let emitter = silhouetteEmitter
        switch inked.kind {
        case let .frame(data):
            return emitter.frame(inked, data: data, in: container).map { Optional($0) }
        case let .group(data):
            return emitter.groupStack(data.children ?? [], flow: flow).map { Optional($0) }
        default:
            return .done(nil)
        }
    }

    /// This emitter, reporting nothing and drawing no text field: the one a silhouette's
    /// inked copy is drawn by, whose warnings the node itself has already given.
    private var silhouetteEmitter: SwiftUINodeEmitter {
        var emitter = self
        emitter.diagnostics = nil
        emitter.scope.textField = nil
        return emitter
    }

    /// Whether a fill or stroke paints anything a shadow is cast by: an enabled paint that is
    /// not fully transparent, as the renderer's `PenFills.hasVisiblePaint` reads it, or a
    /// color read through a variable, which the theme may make anything.
    static func castsPaint(_ fills: PenFills?) -> Bool {
        fills?.all.contains { fill in
            guard fill.isEnabled else { return false }
            if case .variable = fill.solidColor { return true }
            return PenFills.single(fill).hasVisiblePaint
        } ?? false
    }

    /// Whether `node` or anything under it casts a shadow: a shape whose fill or stroke paints,
    /// a line whose stroke does, text and icons always (their glyphs cast, whatever their
    /// paint), and an instance, which the silhouette draws as it is.
    static func castsAnything(_ node: PenNode) -> Bool {
        PenNode.enabledInDocumentOrder([node]).contains { descendant in
            switch descendant.kind {
            case .text, .icon, .ref: true
            case let .frame(data): castsPaint(data.fills) || castsPaint(data.stroke)
            case let .rectangle(data): castsPaint(data.fills) || castsPaint(data.stroke)
            case let .ellipse(data): castsPaint(data.fills) || castsPaint(data.stroke)
            case let .polygon(data): castsPaint(data.fills) || castsPaint(data.stroke)
            case let .path(data): castsPaint(data.fills) || castsPaint(data.stroke)
            case let .line(data): castsPaint(data.stroke)
            default: false
            }
        }
    }
}
