//
//  SwiftUISlot+Discovery.swift
//  Woodcase
//

extension SwiftUISlot {
    /// A frame marked `slot` that the struct draws as a plain frame instead, and why.
    struct Refusal: Friendly {
        /// The slot frame's name, or its id.
        var label: String
        /// Why one view cannot be its content.
        var reason: String
    }

    /// The slots of the component `root`, whose struct is `typeName`, in document order,
    /// and the slot frames it draws as plain frames.
    ///
    /// A slot is a frame of the component's own tree with `slot` set; one inside another
    /// slot's default content, or inside a nested instance, is that content's or that
    /// component's. A frame that spreads its children with `space_between` or
    /// `space_around` is refused — the spacers go between the children, and a caller's
    /// content is one view — as is one whose default content places a child absolutely
    /// in a stack. Names avoid `taken` (the props' and the control's members) and each
    /// other: a slot named as a prop is `<name>Content`.
    static func slots(in root: PenNode, typeName: String, taken: Set<String>) -> (slots: [SwiftUISlot], refused: [Refusal]) {
        var slots: [SwiftUISlot] = []
        var refused: [Refusal] = []
        var names = taken.union(reservedNames)
        var generics: Set<String> = []
        var pending: [(node: PenNode, path: [String])] = ComponentAnalyzer.childNodes(of: root).reversed().map { ($0, []) }
        while let (node, parents) = pending.popLast() {
            let path = parents + [node.common.name ?? node.id]
            guard case let .frame(data) = node.kind, data.slot != nil else {
                pending += ComponentAnalyzer.childNodes(of: node).reversed().map { ($0, path) }
                continue
            }
            let label = node.common.name ?? node.id
            if let justify = data.justifyContent, justify == .spaceBetween || justify == .spaceAround {
                refused.append(Refusal(label: label, reason: "it spreads its children (\(justify.rawValue)), and a caller's content is one view"))
                continue
            }
            var slot = SwiftUISlot(frame: node, path: path.joined(separator: "/"), name: "", genericName: "")
            guard slot.holds(slot.defaultContent) else {
                refused.append(Refusal(label: label, reason: "its default content places a child absolutely in a stack"))
                continue
            }
            // A keyword is back-quoted; its slot takes the name with `Content` instead.
            let identifier = SwiftUIProp.identifier(label)
            let base = String(identifier.filter { $0 != "`" })
            var name = identifier.hasPrefix("`") ? base + "Content" : base
            var counter = 1
            while names.contains(name) || generics.contains(genericName(for: name)) {
                name = counter == 1 ? base + "Content" : base + "Content\(counter)"
                counter += 1
            }
            names.insert(name)
            slot.name = name
            slot.genericName = genericName(for: name)
            generics.insert(slot.genericName)
            if !slot.defaultContent.isEmpty {
                slot.defaultTypeName = typeName + upperFirst(name) + "Default"
            }
            slots.append(slot)
        }
        return (slots, refused)
    }

    /// Names a slot never takes: the view's own members, and the theme it reads.
    private static let reservedNames: Set<String> = ["body", "bodyValue", "theme", "face", "self"]

    /// The generic parameter for a slot named `name`: `Content` for `content`,
    /// `HeaderContent` for `header`.
    private static func genericName(for name: String) -> String {
        let upper = upperFirst(name)
        return upper.hasSuffix("Content") ? upper : upper + "Content"
    }

    /// `name` with its first letter uppercased.
    private static func upperFirst(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}
