//
//  FigmaImagePlaceholderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaImagePlaceholder` is the gray fill that stands in for an image Paste could not
/// fetch, built the same way by the importer and by a caller swapping a failed fetch.
struct FigmaImagePlaceholderTests {
    @Test("The placeholder is the named gray, opaque, with no visibility or blend of its own")
    func plain() {
        let fill = FigmaImagePlaceholder.fill()
        #expect(fill == PenFill.PenColorFill(color: .literal(FigmaImagePlaceholder.gray)))
        #expect(FigmaImagePlaceholder.gray == "#C4C4C4FF")
    }

    @Test("Its opacity is baked into the gray's alpha")
    func opacity() {
        let fill = FigmaImagePlaceholder.fill(enabled: .literal(false), blendMode: .screen, opacity: 0.5)
        #expect(fill.color == .literal("#C4C4C480"))
        #expect(fill.enabled == .literal(false))
        #expect(fill.blendMode == .screen)
    }

    @Test("Replacing an image fill keeps its visibility, blend mode and literal opacity")
    func replacing() {
        let image = PenFill.PenImageFill(enabled: .literal(false), blendMode: .multiply, opacity: .literal(0.5), url: "./images/ab")
        #expect(FigmaImagePlaceholder.fill(replacing: image) == FigmaImagePlaceholder.fill(
            enabled: .literal(false), blendMode: .multiply, opacity: 0.5
        ))
        #expect(FigmaImagePlaceholder.fill(replacing: PenFill.PenImageFill(url: "./x.png")) == FigmaImagePlaceholder.fill())
    }
}
