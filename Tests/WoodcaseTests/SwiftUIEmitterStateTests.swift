//
//  SwiftUIEmitterStateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a component's role and states become in emitted SwiftUI, over `codegen-states.pen`:
/// a button role is a `Button` with a `ButtonStyle`, a toggle a `Toggle` with a
/// `ToggleStyle`, a text input a `TextField`, a select a `Menu` holding a `Picker`, and a
/// state the designer drew is a branch drawing that frame. The goldens
/// (``SwiftUIEmitterComponentGoldenTests``) pin whole files.
struct SwiftUIEmitterStateTests {
    /// The fixture's emitted component files, by type name, and its warnings.
    private static func emitted() throws -> (files: [String: String], diagnostics: [PenDiagnostic]) {
        let collector = PenDiagnosticCollector()
        let result = try SwiftUIFixtures.emit("codegen-states", diagnostics: collector)
        var files: [String: String] = [:]
        for file in result.files where file.path.contains("/Components/") {
            files[URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent] = file.content
        }
        return (files, collector.diagnostics)
    }

    private static func file(_ type: String) throws -> String {
        try #require(try emitted().files[type], "no component \(type)")
    }

    // MARK: - Button

    @Test("A button role is a Button with an action, styled by its own ButtonStyle")
    func buttonIsAButton() throws {
        let file = try Self.file("StatesButton")
        #expect(file.contains("    public let action: () -> Void\n"))
        #expect(file.contains("public init(label: String = \"Continue\", action: @escaping () -> Void = {}) {"))
        #expect(file.contains("        Button(action: action) {\n            face\n        }\n        .buttonStyle(Style(view: self))\n"))
        #expect(file.contains("    private struct Style: ButtonStyle {\n        let view: StatesButton\n"))
        #expect(file.contains("PenStateReader(isPressed: configuration.isPressed) { state in"))
    }

    @Test("Each state the designer drew is a face the style draws, the default the button's label")
    func buttonDrawsDesignedStates() throws {
        let file = try Self.file("StatesButton")
        for face in ["face", "pressedFace", "disabledFace", "hoverFace"] {
            #expect(file.contains("    private var \(face): some View {"), "no \(face)")
        }
        let branches = [
            "                    if state.contains(.disabled) {",
            "                        view.disabledFace",
            "                    } else if state.contains(.pressed) {",
            "                        view.pressedFace",
            "                    } else if state.contains(.hovered) {",
            "                        view.hoverFace",
            "                    } else {",
            "                        configuration.label",
            "                    }",
        ].joined(separator: "\n")
        #expect(file.contains(branches))
    }

    @Test("A drawn state's text still reads the component's prop")
    func variantReadsProps() throws {
        let file = try Self.file("StatesButton")
        #expect(!file.contains("Text(\"Continue\")"))
        let pressed = try #require(file.range(of: "private var pressedFace"))
        #expect(file[pressed.upperBound...].contains("Text(label)"))
    }

    @Test("A state the designer did not draw is its smart default, spelled as modifiers")
    func smartDefaultsAreModifiers() throws {
        let button = try Self.file("StatesButton")
        #expect(button.contains(".penFocusRing(state.contains(.focused), width: 2, offset: 2, cornerRadius: 10)"))
        let link = try Self.file("MoreLink")
        #expect(link.contains("Button(action: action) {"))
        #expect(link.contains(".colorMultiply(Color(white: state.contains(.hovered) ? 0.95 : 1))"))
        #expect(link.contains(".scaleEffect(state.contains(.pressed) ? 0.98 : 1)"))
    }

    @Test("Each state has a preview that pins it")
    func statePreviews() throws {
        let file = try Self.file("StatesButton")
        #expect(file.contains("#Preview {\n    StatesButton()\n}"))
        #expect(file.contains("#Preview(\"pressed\") {\n    StatesButton()\n        .penControlState(.pressed)\n}"))
        #expect(file.contains("#Preview(\"hover\") {\n    StatesButton()\n        .penControlState(.hovered)\n}"))
        #expect(file.contains("#Preview(\"disabled\") {\n    StatesButton()\n        .disabled(true)\n}"))
    }

    // MARK: - Toggle

    @Test("A toggle role is a Toggle bound to isOn, styled by its own ToggleStyle")
    func toggleIsAToggle() throws {
        let file = try Self.file("Switch")
        #expect(file.contains("    @Binding public var isOn: Bool\n"))
        #expect(file.contains("    public init(isOn: Binding<Bool> = .constant(true)) {\n        _isOn = isOn\n    }"))
        #expect(file.contains("        Toggle(isOn: $isOn) {\n            EmptyView()\n        }\n        .toggleStyle(Style(view: self))\n"))
        #expect(file.contains("    private struct Style: ToggleStyle {"))
        #expect(file.contains("if !configuration.isOn {\n                        view.offFace\n                    } else {\n                        view.face\n                    }"))
        #expect(file.contains(".onTapGesture {\n                configuration.isOn.toggle()\n            }"))
        #expect(file.contains("#Preview(\"off\") {\n    Switch(isOn: .constant(false))\n}"))
    }

    @Test("A disabled toggle fades and stops taking the pointer")
    func toggleDisabledSmartDefault() throws {
        let file = try Self.file("Switch")
        #expect(file.contains(".opacity(state.contains(.disabled) ? 0.5 : 1)"))
        #expect(file.contains(".allowsHitTesting(!state.contains(.disabled))"))
    }

    // MARK: - Text input

    @Test("A text input role is a TextField over its text, bound to text and focused by its own FocusState")
    func textInputIsATextField() throws {
        let file = try Self.file("SearchField")
        #expect(file.contains("    @Binding public var text: String\n"))
        #expect(file.contains("    @FocusState private var isFocused: Bool\n"))
        #expect(file.contains("public init(text: Binding<String> = .constant(\"\")) {\n        _text = text\n    }"))
        #expect(file.contains("TextField(\"\", text: $text, prompt: Text(\"Search\").foregroundStyle(Color(hex: 0x94A3B8)))"))
        #expect(file.contains(".textFieldStyle(.plain)"))
        #expect(file.contains(".focused($isFocused)"))
        #expect(file.contains("PenStateReader(isFocused: isFocused) { state in"))
        #expect(!file.contains("Text(\"Search\")\n"))
    }

    @Test("A text input's designed focus is drawn as the smart ring, with a warning: its branch would drop the focus")
    func textInputFocusVariant() throws {
        let (files, diagnostics) = try Self.emitted()
        let file = try #require(files["SearchField"])
        #expect(file.contains(".penFocusRing(state.contains(.focused)"))
        #expect(!file.contains("focusedFace"))
        #expect(file.contains("disabledFace"))
        #expect(diagnostics.contains { $0.message.contains("\"focused\"") && $0.message.contains("SearchField") })
    }

    // MARK: - Select

    @Test("A select role is a Menu holding a Picker over options, its label the component")
    func selectIsAPicker() throws {
        let file = try Self.file("SortSelect")
        #expect(file.contains("    @Binding public var selection: String\n"))
        #expect(file.contains("    public let options: [String]\n"))
        #expect(file.contains("        Menu {\n            Picker(selection: $selection) {\n"))
        #expect(file.contains("ForEach(options, id: \\.self) { option in"))
        #expect(file.contains(".pickerStyle(.inline)"))
        #expect(file.contains("        } label: {\n            face\n        }\n        .menuStyle(.button)\n"))
        #expect(file.contains(".buttonStyle(Style(view: self))"))
    }

    @Test("A state no SwiftUI control reports is a typed variant the caller sets")
    func attributeStateIsAVariant() throws {
        let select = try Self.file("SortSelect")
        #expect(select.contains("    public enum Variant: String, CaseIterable, Sendable {\n        case open\n    }"))
        #expect(select.contains("    public let variant: Variant?\n"))
        #expect(select.contains("if view.variant == .open {"))
        #expect(select.contains("#Preview(\"open\") {\n    SortSelect(variant: .open)\n}"))
        let chip = try Self.file("Chip")
        #expect(chip.contains("public init(variant: Variant? = nil) {"))
        #expect(chip.contains("if variant == .selected {\n                selectedFace\n            } else {\n                face\n            }"))
        #expect(!chip.contains("PenStateReader"))
    }

    // MARK: - Tab bar

    @Test("A tab bar is drawn for its selected tab, a typed enum of its variants")
    func tabBar() throws {
        let result = try SwiftUIFixtures.emit("woodcase-app")
        let file = try #require(result.files.first { $0.path.hasSuffix("/Components/TabBar.swift") }?.content)
        #expect(file.contains("    public enum Tab: String, CaseIterable, Sendable {\n        case home\n        case log\n"))
        #expect(file.contains("    public let selected: Tab?\n"))
        #expect(file.contains("if selected == .home {\n                homeFace\n"))
        #expect(file.contains(".accessibilityAddTraits(.isTabBar)"))
        #expect(file.contains("#Preview(\"home\") {\n    TabBar(selected: .home)\n}"))
    }

    // MARK: - Diagnostics and support

    @Test("A component with states no longer carries the default-state notice")
    func noDefaultStateNotice() throws {
        let (_, diagnostics) = try Self.emitted()
        #expect(!diagnostics.contains { $0.message.contains("its states are not emitted yet") })
    }

    @Test("The support file reads and pins a control's state")
    func supportTemplate() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+States.swift"])
        #expect(support.contains("public struct PenControlState: OptionSet"))
        #expect(support.contains("public extension View {\n    /// Draws the generated controls"))
        #expect(support.contains("func penControlState(_ state: PenControlState) -> some View"))
        #expect(support.contains("struct PenStateReader<Content: View>: View"))
        #expect(support.contains("func penFocusRing("))
    }
}
