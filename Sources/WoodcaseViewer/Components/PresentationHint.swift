//
//  PresentationHint.swift
//  WoodcaseViewer
//

import Elementary
import Foundation

/// The way *out* of presentation mode, said once as you go in.
///
/// Presentation hides every control there is, the ones that would have told you how to
/// leave included, so the mode has to say it itself. It flashes on entry and fades: a
/// label that stayed would be one more thing on a screen whose whole point is that there
/// is nothing on it but the artboard.
///
/// It sits outside ``RenderRegion`` on purpose. The region is swapped on every change and
/// every step, and a hint that re-flashed each time an artboard arrived would blink at
/// you all the way through a file.
public struct PresentationHint: HTML {
    /// Creates the hint.
    public init() {}

    /// What it says — both keys, because both work and neither is guessable from a
    /// screen with nothing on it.
    public static let text = "Press f or Escape to exit"

    public var body: some HTML {
        div(.class("v-present-hint"), .id("v-present-hint")) { Self.text }
    }
}
