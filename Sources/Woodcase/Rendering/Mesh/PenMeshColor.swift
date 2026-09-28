//
//  PenMeshColor.swift
//  Woodcase
//

import Foundation

/// A mesh gradient vertex colour: sRGB-encoded, unpremultiplied, each channel in `0...1`.
///
/// Pen blends a mesh's colours on the encoded channel values, with no linearisation and
/// no perceptual space, so the tessellator does the same. Unlike ``PenColorParser`` this
/// type needs no CoreGraphics, which keeps the mesh core buildable on Linux. Pen reads a
/// mesh's colour strings its own way, not by ``PenHexColor``'s grammar
/// (``init(penMesh:)``).
public struct PenMeshColor: Friendly {
    /// Creates a colour from its channels.
    ///
    /// - Parameters:
    ///   - red: The sRGB-encoded red channel, `0...1`.
    ///   - green: The sRGB-encoded green channel, `0...1`.
    ///   - blue: The sRGB-encoded blue channel, `0...1`.
    ///   - alpha: The opacity, `0...1`; unpremultiplied.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The sRGB-encoded red channel, `0...1`.
    public var red: Double

    /// The sRGB-encoded green channel, `0...1`.
    public var green: Double

    /// The sRGB-encoded blue channel, `0...1`.
    public var blue: Double

    /// The opacity, `0...1`. The colour channels are not multiplied by it.
    public var alpha: Double

    /// Opaque black: what the renderer paints for a vertex colour that is still a
    /// variable. A string is read as Pen reads it (``init(penMesh:)``).
    public static let black = PenMeshColor(red: 0, green: 0, blue: 0)
}
