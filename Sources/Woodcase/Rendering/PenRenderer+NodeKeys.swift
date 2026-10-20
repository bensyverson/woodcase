import CoreGraphics

/// The per-kind keys the renderer reads off a node, one switch each.
extension PenRenderer {
    /// Extracts the effects from a node's kind-specific data.
    static func effects(for node: PenNode) -> PenEffects? {
        switch node.kind {
        case let .rectangle(data): data.effects
        case let .ellipse(data): data.effects
        case let .polygon(data): data.effects
        case let .line(data): data.effects
        case let .path(data): data.effects
        case let .frame(data): data.effects
        case let .group(data): data.effects
        case let .text(data): data.effects
        case let .icon(data): data.effects
        case let .browser(data): data.effects
        default: nil
        }
    }

    /// The node's own blend mode (``PenNode/blendMode``), stored in its metadata.
    static func blendMode(for node: PenNode) -> PenBlendMode? {
        node.blendMode
    }

    /// Extracts the fills from a node's kind-specific data; `nil` for kinds without fills.
    static func fills(for node: PenNode) -> PenFills? {
        switch node.kind {
        case let .rectangle(data): data.fills
        case let .ellipse(data): data.fills
        case let .polygon(data): data.fills
        case let .path(data): data.fills
        case let .frame(data): data.fills
        case let .text(data): data.fills
        case let .icon(data): data.fills
        default: nil
        }
    }
}
