//
//  SwiftUIEmitter+Fonts.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The text font faces `node` and its enabled descendants set: a literal family as
    /// written, and for a family variable every value it takes under any theme
    /// (``SwiftUITheme/Token/Case/string``), each at the node's weight and style — what
    /// `woodcase generate swiftui` bundles into `Sources/<Module>/Resources/`, so the
    /// package draws its text in its own faces.
    static func fontFaces(in node: PenNode, theme: SwiftUITheme?) -> Set<PenFontFace> {
        guard node.common.enabled?.literalValue != false else { return [] }
        switch node.kind {
        case let .text(data):
            let families: [String] = switch data.fontFamily {
            case let .literal(family)?: [family]
            case let .variable(name)?: theme?.tokens[name]?.cases.compactMap(\.string) ?? []
            case nil: []
            }
            return Set(families.map {
                PenFontFace(family: $0, fontWeight: data.fontWeight?.literalValue, fontStyle: data.fontStyle?.literalValue)
            })
        case let .frame(data):
            return (data.children ?? []).reduce(into: Set<PenFontFace>()) { $0.formUnion(fontFaces(in: $1, theme: theme)) }
        case let .group(data):
            return (data.children ?? []).reduce(into: Set<PenFontFace>()) { $0.formUnion(fontFaces(in: $1, theme: theme)) }
        default:
            return []
        }
    }
}
