//
//  SwiftUINodeEmitter+GroupSilhouette.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The silhouette a group's shadows are cast by: its children, placed as the group
    /// places them, each drawn as the region it covers in opaque black — or `nil` when
    /// nothing in the group covers anything.
    ///
    /// Pen casts a group's shadow from what its descendants cover, not from what they paint
    /// (`render-group-shadows.pen`): a translucent child casts a full-strength shadow, a
    /// stroke that reaches outside its shape grows the silhouette by that much, a frame
    /// casts its box and not its own children, a nested group casts what its children
    /// cover, and a line, a child's own shadows, blur, opacity and blend mode cast nothing.
    ///
    /// - Parameters:
    ///   - children: The group's children.
    ///   - flow: How the group sits in a stack, or `nil` when it is placed by its `x`/`y`
    ///     (``groupStack(_:flow:)``).
    func groupSilhouette(_ children: [PenNode], flow: GroupFlow? = nil) -> SwiftUIViewCode? {
        let inked = children.compactMap(Self.inked)
        guard !inked.isEmpty else { return nil }
        return groupStack(inked, flow: flow)
    }

    /// `node` as it stands in a group's silhouette, or `nil` for a node that covers nothing
    /// there: a line, and any kind the emitter does not draw.
    static func inked(_ node: PenNode) -> PenNode? {
        var node = node
        node.common.opacity = nil
        switch node.kind {
        case var .frame(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            data.children = boxOnly(data.children, of: node)
            node.kind = .frame(data)
        case var .rectangle(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            node.kind = .rectangle(data)
        case var .ellipse(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            node.kind = .ellipse(data)
        case var .polygon(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            node.kind = .polygon(data)
        case var .path(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            node.kind = .path(data)
        case var .text(data):
            data.fills = ink
            data.stroke = data.stroke.map { _ in ink }
            data.effects = nil
            data.blendMode = nil
            node.kind = .text(data)
        case var .icon(data):
            data.fills = ink
            data.effects = nil
            data.blendMode = nil
            node.kind = .icon(data)
        case var .group(data):
            data.children = data.children?.compactMap(inked)
            data.effects = nil
            data.blendMode = nil
            node.kind = .group(data)
        default:
            return nil
        }
        return node
    }

    /// The paint a silhouette is drawn in: opaque black. Only its coverage matters.
    private static let ink = PenFills.single(.shorthand("#000000"))

    /// A frame's children in its silhouette: none when the frame's size is fixed, since it
    /// casts its box alone; otherwise all of them, transparent, so a frame sized by its
    /// content keeps its size without casting its content.
    private static func boxOnly(_ children: [PenNode]?, of frame: PenNode) -> [PenNode]? {
        if case .fixed = PenLayoutEngine.widthSizing(of: frame), case .fixed = PenLayoutEngine.heightSizing(of: frame) {
            return nil
        }
        return children?.map { child in
            var hidden = child
            hidden.common.opacity = .literal(0)
            return hidden
        }
    }
}
