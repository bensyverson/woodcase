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

    /// Extracts the blend mode from a node's kind-specific data.
    static func blendMode(for node: PenNode) -> PenBlendMode? {
        switch node.kind {
        case let .rectangle(data): data.blendMode
        case let .ellipse(data): data.blendMode
        case let .polygon(data): data.blendMode
        case let .line(data): data.blendMode
        case let .path(data): data.blendMode
        case let .frame(data): data.blendMode
        case let .group(data): data.blendMode
        case let .text(data): data.blendMode
        case let .icon(data): data.blendMode
        default: nil
        }
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
