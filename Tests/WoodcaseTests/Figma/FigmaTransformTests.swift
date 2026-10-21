//
//  FigmaTransformTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A Figma transform decomposed into Pen's position, counter-clockwise turn and flips.
struct FigmaTransformTests {
    /// The Figma matrix that turns by `degrees` clockwise on screen, as Figma's UI shows a
    /// negative rotation, with a translation.
    private static func turned(_ degrees: Double, x: Double = 0, y: Double = 0) -> FigmaTransform {
        let radians = degrees * .pi / 180
        return FigmaTransform(m00: cos(radians), m01: -sin(radians), m02: x, m10: sin(radians), m11: cos(radians), m12: y)
    }

    @Test("The identity is a position and nothing else")
    func identity() {
        let placement = FigmaTransform(m00: 1, m01: 0, m02: 12, m10: 0, m11: 1, m12: 34).placement
        #expect(placement == FigmaTransform.Placement(x: 12, y: 34, rotation: 0, flipX: false, flipY: false, isSkewed: false))
    }

    @Test("A clockwise turn on screen is Pen's negative, counter-clockwise rotation")
    func rotation() {
        let placement = Self.turned(30, x: 5, y: 6).placement
        #expect(abs(placement.rotation + 30) < 1e-9)
        #expect(placement.x == 5 && placement.y == 6 && !placement.flipX && !placement.flipY)
    }

    @Test("A mirror is a flip; a vertical one stays vertical rather than becoming a flip and a half turn")
    func flips() {
        let horizontal = FigmaTransform(m00: -1, m01: 0, m02: 80, m10: 0, m11: 1, m12: 0).placement
        #expect(horizontal.flipX && !horizontal.flipY && horizontal.rotation == 0)
        let vertical = FigmaTransform(m00: 1, m01: 0, m02: 0, m10: 0, m11: -1, m12: 80).placement
        #expect(vertical.flipY && !vertical.flipX && vertical.rotation == 0)
    }

    @Test("A turned mirror recomposes to the same matrix")
    func turnedMirror() {
        let figma = FigmaTransform(m00: -0.8, m01: 0.6, m02: 3, m10: 0.6, m11: 0.8, m12: 4)
        let placement = figma.placement
        let radians = -placement.rotation * .pi / 180
        let signX = placement.flipX ? -1.0 : 1.0, signY = placement.flipY ? -1.0 : 1.0
        #expect(abs(cos(radians) * signX - figma.m00) < 1e-9)
        #expect(abs(sin(radians) * signX - figma.m10) < 1e-9)
        #expect(abs(-sin(radians) * signY - figma.m01) < 1e-9)
        #expect(abs(cos(radians) * signY - figma.m11) < 1e-9)
    }

    @Test("A skew or a scale is reported, since Pen's transform has neither")
    func skew() {
        #expect(FigmaTransform(m00: 1, m01: 0.5, m02: 0, m10: 0, m11: 1, m12: 0).placement.isSkewed)
        #expect(FigmaTransform(m00: 2, m01: 0, m02: 0, m10: 0, m11: 2, m12: 0).placement.isSkewed)
        #expect(!Self.turned(15).placement.isSkewed)
    }
}
