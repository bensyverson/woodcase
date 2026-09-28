/// Per-node property overrides for animation.
///
/// The consuming app interpolates keyframes at a given time `t`, builds a
/// `[String: NodeOverrides]` dictionary keyed by node ID, and passes it to
/// ``PenRenderer/render(_:layoutRects:size:scale:colorSpace:rootNodeID:overrides:imageProvider:)``.
/// Woodcase doesn't know about keyframes or time — it just renders what it's told.
///
/// Only non-nil properties are applied; nil properties fall through to the
/// node's original values.
public struct NodeOverrides: Friendly {
    /// Override the node's x position (in points).
    public var x: Double?

    /// Override the node's y position (in points).
    public var y: Double?

    /// Override the node's width (in points).
    public var width: Double?

    /// Override the node's height (in points).
    public var height: Double?

    /// Override the node's rotation (in degrees).
    public var rotation: Double?

    /// Override the node's opacity (0.0–1.0).
    public var opacity: Double?

    /// Override whether the node is enabled (visible).
    public var enabled: Bool?

    /// Override the node's fills.
    public var fills: PenFills?

    /// Creates a set of node overrides.
    ///
    /// All parameters default to `nil`, meaning the node's original value is used.
    public init(
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        rotation: Double? = nil,
        opacity: Double? = nil,
        enabled: Bool? = nil,
        fills: PenFills? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.opacity = opacity
        self.enabled = enabled
        self.fills = fills
    }
}
