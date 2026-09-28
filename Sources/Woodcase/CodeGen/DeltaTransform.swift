//
//  DeltaTransform.swift
//  Woodcase
//

/// A state variant's turn and flips, as the variant's node carries them: the value of a
/// ``DeltaProperty/transform`` change.
///
/// Typed so no emitter parses a target's spelling of it: React writes it into its CSS
/// custom property (``StateEmitter``), SwiftUI would write `.rotationEffect` and a
/// negative `.scaleEffect`.
public struct DeltaTransform: Friendly {
    /// Creates a transform.
    public init(rotation: Double?, flipX: Bool, flipY: Bool) {
        self.rotation = rotation
        self.flipX = flipX
        self.flipY = flipY
    }

    /// The variant's literal rotation in degrees, or `nil` when it has none — or one bound
    /// to a variable, which the diff does not resolve.
    public var rotation: Double?

    /// Whether the variant is mirrored left to right.
    public var flipX: Bool

    /// Whether the variant is mirrored top to bottom.
    public var flipY: Bool
}
