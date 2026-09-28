//
//  ChangeCategoryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ChangeCategoryTests {
    // MARK: - Common Property Changes

    @Test("Name change is render-only")
    func nameChangeIsRenderOnly() {
        let old = PenNodeCommon(name: "Button")
        let new = PenNodeCommon(name: "PrimaryButton")
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .renderOnly)
    }

    @Test("Opacity change is render-only")
    func opacityChangeIsRenderOnly() {
        let old = PenNodeCommon(opacity: .literal(1.0))
        let new = PenNodeCommon(opacity: .literal(0.5))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .renderOnly)
    }

    @Test("FlipX change is render-only")
    func flipXChangeIsRenderOnly() {
        let old = PenNodeCommon(flipX: .literal(false))
        let new = PenNodeCommon(flipX: .literal(true))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .renderOnly)
    }

    @Test("X position change is layout-affecting")
    func xChangeIsLayout() {
        let old = PenNodeCommon(x: .literal(0))
        let new = PenNodeCommon(x: .literal(100))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("Y position change is layout-affecting")
    func yChangeIsLayout() {
        let old = PenNodeCommon(y: .literal(0))
        let new = PenNodeCommon(y: .literal(50))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("Rotation change is layout-affecting")
    func rotationChangeIsLayout() {
        let old = PenNodeCommon(rotation: .literal(0))
        let new = PenNodeCommon(rotation: .literal(45))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("Enabled change is layout-affecting")
    func enabledChangeIsLayout() {
        let old = PenNodeCommon(enabled: .literal(true))
        let new = PenNodeCommon(enabled: .literal(false))
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("LayoutPosition change is layout-affecting")
    func layoutPositionChangeIsLayout() {
        let old = PenNodeCommon()
        let new = PenNodeCommon(layoutPosition: .absolute)
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("Theme change is layout-affecting")
    func themeChangeIsLayout() {
        let old = PenNodeCommon(theme: ["mode": "light"])
        let new = PenNodeCommon(theme: ["mode": "dark"])
        #expect(ChangeCategory.categorize(oldCommon: old, newCommon: new) == .layout)
    }

    @Test("No change returns nil")
    func noChangeReturnsNil() {
        let common = PenNodeCommon(name: "Button", x: .literal(10))
        #expect(ChangeCategory.categorize(oldCommon: common, newCommon: common) == nil)
    }

    // MARK: - Kind Property Changes

    @Test("Width change is layout-affecting")
    func widthChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(100)))
        let new = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(200)))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Height change is layout-affecting")
    func heightChangeIsLayout() {
        let old = PenNode.Kind.rectangle(PenNode.RectangleData(height: .fixed(50)))
        let new = PenNode.Kind.rectangle(PenNode.RectangleData(height: .fixed(100)))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Fill-only change is render-only")
    func fillOnlyChangeIsRenderOnly() {
        let old = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(100), height: .fixed(50),
            fills: .single(.shorthand("red"))
        ))
        let new = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(100), height: .fixed(50),
            fills: .single(.shorthand("blue"))
        ))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Gap change is layout-affecting")
    func gapChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(gap: .literal(8)))
        let new = PenNode.Kind.frame(PenNode.FrameData(gap: .literal(16)))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Padding change is layout-affecting")
    func paddingChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(padding: .uniform(.literal(8))))
        let new = PenNode.Kind.frame(PenNode.FrameData(padding: .uniform(.literal(16))))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Text content change is layout-affecting")
    func textContentChangeIsLayout() {
        let old = PenNode.Kind.text(PenNode.TextData(content: .literal("Hello")))
        let new = PenNode.Kind.text(PenNode.TextData(content: .literal("Hello World")))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Font size change is layout-affecting")
    func fontSizeChangeIsLayout() {
        let old = PenNode.Kind.text(PenNode.TextData(fontSize: .literal(14)))
        let new = PenNode.Kind.text(PenNode.TextData(fontSize: .literal(24)))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Text align change is render-only")
    func textAlignChangeIsRenderOnly() {
        let old = PenNode.Kind.text(PenNode.TextData(textAlign: .left))
        let new = PenNode.Kind.text(PenNode.TextData(textAlign: .center))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Kind type change is layout-affecting")
    func kindTypeChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData())
        let new = PenNode.Kind.text(PenNode.TextData())
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("No kind change returns nil")
    func noKindChangeReturnsNil() {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(100), fills: .single(.shorthand("red"))
        ))
        #expect(ChangeCategory.categorize(oldKind: kind, newKind: kind) == nil)
    }

    @Test("CornerRadius change is render-only")
    func cornerRadiusChangeIsRenderOnly() {
        let old = PenNode.Kind.frame(PenNode.FrameData(cornerRadius: .uniform(.literal(4))))
        let new = PenNode.Kind.frame(PenNode.FrameData(cornerRadius: .uniform(.literal(8))))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("BlendMode change is render-only")
    func blendModeChangeIsRenderOnly() {
        let old = PenNode.Kind.frame(PenNode.FrameData(blendMode: .normal))
        let new = PenNode.Kind.frame(PenNode.FrameData(blendMode: .multiply))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Layout direction change is layout-affecting")
    func layoutDirectionChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(layout: .horizontal))
        let new = PenNode.Kind.frame(PenNode.FrameData(layout: .vertical))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("JustifyContent change is layout-affecting")
    func justifyContentChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(justifyContent: .start))
        let new = PenNode.Kind.frame(PenNode.FrameData(justifyContent: .center))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("AlignItems change is layout-affecting")
    func alignItemsChangeIsLayout() {
        let old = PenNode.Kind.frame(PenNode.FrameData(alignItems: .start))
        let new = PenNode.Kind.frame(PenNode.FrameData(alignItems: .center))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .layout)
    }

    @Test("Slot change is render-only")
    func slotChangeIsRenderOnly() {
        let old = PenNode.Kind.frame(PenNode.FrameData(slot: ["text"]))
        let new = PenNode.Kind.frame(PenNode.FrameData(slot: ["text", "icon"]))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Stroke change is render-only")
    func strokeChangeIsRenderOnly() {
        let old = PenNode.Kind.rectangle(PenNode.RectangleData(
            strokeWidth: .uniform(.literal(1))
        ))
        let new = PenNode.Kind.rectangle(PenNode.RectangleData(
            strokeWidth: .uniform(.literal(2))
        ))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Effects change is render-only")
    func effectsChangeIsRenderOnly() {
        let old = PenNode.Kind.rectangle(PenNode.RectangleData())
        let new = PenNode.Kind.rectangle(PenNode.RectangleData(
            effects: .single(.blur(PenEffect.PenBlurEffect(radius: .literal(4))))
        ))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    // MARK: - Group (no layout properties of its own)

    @Test("Group blendMode change is render-only")
    func groupBlendModeChangeIsRenderOnly() {
        let old = PenNode.Kind.group(PenNode.GroupData(blendMode: .normal))
        let new = PenNode.Kind.group(PenNode.GroupData(blendMode: .multiply))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }

    @Test("Group effects change is render-only")
    func groupEffectsChangeIsRenderOnly() {
        let old = PenNode.Kind.group(PenNode.GroupData())
        let new = PenNode.Kind.group(PenNode.GroupData(
            effects: .single(.blur(PenEffect.PenBlurEffect(radius: .literal(4))))
        ))
        #expect(ChangeCategory.categorize(oldKind: old, newKind: new) == .renderOnly)
    }
}
