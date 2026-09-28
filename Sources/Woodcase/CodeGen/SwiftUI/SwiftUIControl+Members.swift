//
//  SwiftUIControl+Members.swift
//  Woodcase
//

extension SwiftUIControl {
    /// One member the control adds to the component's view struct after its props: a
    /// declaration, and the init's parameter and assignment when the caller sets it.
    struct Member: Friendly {
        /// The declaration, without indentation: `public let action: () -> Void`.
        var declaration: String

        /// The init's parameter, or `nil` for a member the caller never sets.
        var parameter: String?

        /// The init's statement that stores the parameter, without indentation.
        var assignment: String?
    }

    /// What the control adds to the struct: a button's `action`, a toggle's `isOn`, a text
    /// field's `text` and focus, a picker's `selection` and `options`, and the caller's
    /// ``enumName`` pick where the component has one.
    ///
    /// A binding defaults to a constant, so the preview and a call without one draw what
    /// Pen draws: a toggle on, as its component frame is, a field and a selection empty.
    var members: [Member] {
        var members: [Member] = []
        switch kind {
        case .button:
            members.append(Member(
                declaration: "public let action: () -> Void",
                parameter: "action: @escaping () -> Void = {}",
                assignment: "self.action = action"
            ))
        case .toggle:
            members.append(binding("isOn", type: "Bool", default: "true"))
        case .textField:
            members.append(binding("text", type: "String", default: "\"\""))
            members.append(Member(declaration: "@FocusState private var isFocused: Bool"))
        case .picker:
            members.append(binding("selection", type: "String", default: "\"\""))
            members.append(Member(
                declaration: "public let options: [String]",
                parameter: "options: [String] = []",
                assignment: "self.options = options"
            ))
        case .tabBar, .plain:
            break
        }
        if !cases.isEmpty {
            members.append(Member(
                declaration: "public let \(enumProperty): \(enumName)?",
                parameter: "\(enumProperty): \(enumName)? = nil",
                assignment: "self.\(enumProperty) = \(enumProperty)"
            ))
        }
        return members
    }

    /// The names the members declare, which no prop may take.
    var memberNames: [String] {
        var names: [String] = switch kind {
        case .button: ["action"]
        case .toggle: ["isOn"]
        case .textField: ["text", "isFocused"]
        case .picker: ["selection", "options"]
        case .tabBar, .plain: []
        }
        if !cases.isEmpty {
            names.append(enumProperty)
        }
        return names
    }

    /// The enum a caller picks a face by, with a doc comment, or no lines when there is none.
    var enumLines: [String] {
        guard !cases.isEmpty else { return [] }
        let what = kind == .tabBar ? "The tabs the bar is drawn with selected" : "The states a caller draws the view in"
        return ["    /// \(what).", "    public enum \(enumName): String, CaseIterable, Sendable {"]
            + cases.map { "        case \($0)" }
            + ["    }"]
    }

    /// A two-way binding the caller passes, stored as `@Binding`.
    private func binding(_ name: String, type: String, default value: String) -> Member {
        Member(
            declaration: "@Binding public var \(name): \(type)",
            parameter: "\(name): Binding<\(type)> = .constant(\(value))",
            assignment: "_\(name) = \(name)"
        )
    }
}

extension SwiftUIControl.Member {
    /// A member the caller never sets.
    init(declaration: String) {
        self.init(declaration: declaration, parameter: nil, assignment: nil)
    }
}
