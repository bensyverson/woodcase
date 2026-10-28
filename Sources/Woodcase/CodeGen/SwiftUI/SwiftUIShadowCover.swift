//
//  SwiftUIShadowCover.swift
//  Woodcase
//

/// Which frames' fills cover everything their descendants cast into their outer shadows, so
/// a frame's shadow is cast by its own silhouette alone and the page needs no inked copy of
/// its content (``SwiftUINodeEmitter/contentSilhouette(of:in:flow:)``).
///
/// A frame's children add nothing to its silhouette when the frame's fill paints — its whole
/// shape is then in the silhouette — and every piece of its descendants' silhouettes
/// (``Piece``) lies inside that shape. The test is conservative throughout, so a frame it
/// cannot bound keeps the copy:
///
/// - it is decided from Pen's layout of the document, ref-expanded and resolved, under every
///   combination of the document's theme axes, and must hold under each;
/// - a turned or flipped descendant, a descendant the layout did not place, a kind with no
///   bounded silhouette, a radius left as a variable, and a document with more than
///   ``maximumThemes`` theme combinations are never covered.
struct SwiftUIShadowCover: Friendly {
    /// The ids of the frames whose fill covers everything their descendants cast.
    var covered: Set<String> = []

    /// The most theme combinations laid out; a document with more covers nothing.
    static let maximumThemes = 8

    /// No frame covered.
    init() {}

    /// The frames of `document` whose fills cover their descendants' silhouettes. Only a frame
    /// with an outer shadow, a painting fill, no clip and children is examined; a document
    /// with none is not laid out at all.
    init(document: PenDocument) {
        guard PenNode.enabledInDocumentOrder(document.children).contains(where: Self.isCandidate) else { return }
        // An instance the emitter inlines draws the expansion's copy, under the expansion's ids.
        let expanded = PenRefExpander.expand(document, for: .canvas)
        var covered = Set(PenNode.enabledInDocumentOrder(expanded.children).filter(Self.isCandidate).map(\.id))
        let themes = Self.themes(of: document)
        guard !themes.isEmpty else { return }
        for theme in themes {
            let resolved = PenVariableResolver.resolve(expanded, theme: theme)
            let rects = PenLayoutEngine.layout(resolved)
            let frames = PenNode.enabledInDocumentOrder(resolved.children).filter { covered.contains($0.id) }
            covered.formIntersection(frames.filter { Self.covers($0, rects: rects) }.map(\.id))
            if covered.isEmpty { return }
        }
        self.covered = covered
    }

    /// Whether `node` is a frame whose shadow could be cast by its fill alone: it has an
    /// enabled outer shadow, a fill that paints, no clip (a clipping one is decided already)
    /// and children.
    private static func isCandidate(_ node: PenNode) -> Bool {
        guard case let .frame(data) = node.kind, data.clip?.literalValue != true,
              let children = data.children, !children.isEmpty,
              SwiftUINodeEmitter.castsPaint(data.fills)
        else { return false }
        return data.effects?.all.contains { effect in
            guard case let .shadow(shadow) = effect else { return false }
            return shadow.enabled?.literalValue != false && shadow.shadowType != .inner
        } == true
    }

    /// Every combination of the document's theme axes, each as the root theme to resolve
    /// under; one empty theme for a document with none, and none past ``maximumThemes``.
    private static func themes(of document: PenDocument) -> [[String: String]] {
        var combinations: [[String: String]] = [[:]]
        for (axis, values) in (document.themes ?? [:]).sorted(by: { $0.key < $1.key }) where !values.isEmpty {
            combinations = combinations.flatMap { theme in
                values.map { value in theme.merging([axis: value]) { _, new in new } }
            }
            if combinations.count > maximumThemes { return [] }
        }
        return combinations
    }

    /// Whether `frame`'s fill covers every piece of its descendants' silhouettes, in
    /// `rects`' layout.
    private static func covers(_ frame: PenNode, rects: [String: PenRect]) -> Bool {
        guard case let .frame(data) = frame.kind, let box = rects[frame.id], box.width > 0, box.height > 0,
              let corners = (data.cornerRadius ?? .uniform(.literal(0))).resolve(),
              SwiftUINodeEmitter.castsPaint(data.fills)
        else { return false }
        let shape = Piece(x: 0, y: 0, width: box.width, height: box.height, corners: corners)
        guard let pieces = Piece.silhouette(of: data.children ?? [], rects: rects) else { return false }
        return pieces.allSatisfy { shape.contains($0) }
    }
}
