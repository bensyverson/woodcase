//
//  ReactSlot.swift
//  Woodcase
//

/// One slot of a generated React component: a frame the designer marked `slot`, which a
/// caller fills with markup of its own.
///
/// The component takes an optional `React.ReactNode` prop per slot, named for the frame
/// (`list` for "List"), and the slot frame's element renders it where Pen draws the
/// frame's children. The frame's own children are the slot's **default content**, the
/// prop's value when the caller passes none: `{list === undefined ? (<>…</>) : list}`. A
/// caller that passes `null` — an instance whose fill is empty — shows nothing, which is
/// not the default. A slot with no children renders the prop alone.
struct ReactSlot: Friendly {
    /// The slot frame, in the component's own tree.
    var frame: PenNode

    /// The prop: `list`, `actions`.
    var name: String

    /// The frame's children: the default content.
    var defaultContent: [PenNode] {
        ComponentAnalyzer.childNodes(of: frame)
    }

    /// The frame's layout, which places the content a caller passes.
    var layout: PenLayoutDirection {
        if case let .frame(data) = frame.kind { data.layout ?? .horizontal } else { .none }
    }

    /// The frame's data, whose box and padding the content a caller passes is laid out in.
    var frameData: PenNode.FrameData? {
        if case let .frame(data) = frame.kind { data } else { nil }
    }

    /// The slots of `component`, in document order.
    ///
    /// A slot is a frame of the component's own tree with `slot` set; a frame inside
    /// another slot's default content belongs to that content, and one inside a nested
    /// instance to that instance's component, so neither is one. Names avoid the
    /// component's props and the props every component takes, JavaScript's reserved words
    /// and each other: a clash takes `Content` after it (`titleContent`), then a number.
    ///
    /// - Parameter component: The component.
    /// - Returns: Its slots.
    static func slots(of component: ComponentDefinition) -> [ReactSlot] {
        var taken = reservedNames.union(component.props.map(\.name))
        taken.formUnion(component.states.filter(\.isStructural).map(\.name))
        var slots: [ReactSlot] = []
        var pending: [PenNode] = ComponentAnalyzer.childNodes(of: component.sourceNode).reversed()
        while let node = pending.popLast() {
            guard case let .frame(data) = node.kind, data.slot != nil else {
                pending += ComponentAnalyzer.childNodes(of: node).reversed()
                continue
            }
            let base = propName(node.common.name ?? node.id)
            var name = base
            var counter = 1
            while taken.contains(name) || keywords.contains(name) {
                name = counter == 1 ? base + "Content" : base + "Content\(counter)"
                counter += 1
            }
            taken.insert(name)
            slots.append(ReactSlot(frame: node, name: name))
        }
        return slots
    }

    /// The props every component may take, and React's own: no slot is named for one.
    private static let reservedNames: Set<String> = [
        "className", "style", "checked", "disabled", "href", "selected", "children", "key", "ref",
    ]

    /// JavaScript's reserved words, which a destructured prop cannot be named.
    private static let keywords: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "enum", "export", "extends", "false", "finally", "for", "function", "if", "implements",
        "import", "in", "instanceof", "interface", "let", "new", "null", "package", "private", "protected",
        "public", "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof", "var",
        "void", "while", "with", "yield", "undefined",
    ]

    /// `name` as a prop: lower camel case, `content` when it holds no letter or digit, and
    /// `_` before a leading digit.
    private static func propName(_ name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return "content" }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        let camel = first.lowercased() + rest.joined()
        return camel.first?.isNumber == true ? "_" + camel : camel
    }
}
