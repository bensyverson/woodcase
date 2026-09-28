//
//  StateEffect.swift
//  Woodcase
//

/// A visual effect a smart-default state applies to the whole component, named by what it
/// does rather than by any target's way of doing it.
///
/// A designer's own state variant is a set of ``StateDelta``s diffed from the design; a
/// state the design does not draw falls back to ``RoleStateMapping/smartEffects(for:)``,
/// which holds these instead. Each emitter spells every case: React as CSS
/// (``StateEmitter``), SwiftUI as view modifiers.
public enum StateEffect: Friendly {
    /// Multiplies every color of the component by `brightness`: `1` leaves it unchanged,
    /// `0` turns it black. React writes `filter: brightness(…)`.
    case dim(brightness: Double)

    /// Scales the component about its center by `factor`. React writes
    /// `transform: scale(…)`, and leaves it out when the component's root is rotated or
    /// flipped, whose own `transform` it would replace.
    case scale(factor: Double)

    /// Draws the whole component, children included, at `opacity`. React writes `opacity`.
    case fade(opacity: Double)

    /// Rings the component's bounds with a solid line `width` points wide, `offset` points
    /// outside them, in the component's foreground color. React writes an `outline` in
    /// `currentColor` with an `outline-offset`.
    case focusRing(width: Double, offset: Double)

    /// The component stops taking pointer input, so no hover or press reaches it. React
    /// writes `pointer-events: none`.
    case ignoresPointer
}
