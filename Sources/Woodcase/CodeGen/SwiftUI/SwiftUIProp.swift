//
//  SwiftUIProp.swift
//  Woodcase
//

/// One prop of a generated component, as its view struct declares and reads it: a
/// `public let` of a SwiftUI type, an init parameter defaulted to what the component
/// draws, and the node whose paint or text reads it.
///
/// A prop is bound only where the body can read it: a text prop on a `text` node (its
/// `Text` reads the `String`), a colour prop on a node whose first paint is a solid colour
/// (that layer is the `Color`), an image prop on a node whose first paint is a local image
/// (that layer draws the `Image`, resizable, placed by the fill's mode). Callers pass an
/// `Image` rather than a URL, so a view is free to hand in any image, not only a bundled one.
struct SwiftUIProp: Friendly {
    /// What the prop carries, and so its Swift type.
    enum Kind: String, Friendly {
        /// A text node's copy: `String`.
        case text
        /// A solid colour: `Color`.
        case color
        /// An image fill: `Image`.
        case image

        /// The Swift type the struct declares the prop as.
        var swiftType: String {
            switch self {
            case .text: "String"
            case .color: "Color"
            case .image: "Image"
            }
        }
    }

    /// The prop's Swift identifier.
    var name: String

    /// What it carries.
    var kind: Kind

    /// The analyzed prop it comes from.
    var definition: PropDefinition

    /// The parameter's default: what the component draws when no instance overrides it.
    var defaultValue: String

    /// The theme's colour a colour prop defaults to, when its default is a variable: the
    /// prop is then optional, and the body reads ``themedRead``.
    var themedDefault: SwiftUITheme.Token?

    /// The prop `definition` becomes on `target`, the node its path names, or `nil` when
    /// the body cannot read it there. A colour default that names a variable of `theme` is
    /// `nil`, read through the theme; one the emitter cannot write (a malformed colour, a
    /// variable the theme lacks) is named in `unemitted` and falls back to clear.
    init?(_ definition: PropDefinition, target: PenNode?, theme: SwiftUITheme? = nil, unemitted: inout [String]) {
        guard let target, let kind = Self.kind(of: definition.type, on: target) else { return nil }
        name = SwiftUIProp.identifier(definition.name)
        self.kind = kind
        self.definition = definition
        let spelling: String? = if case let .string(value)? = definition.defaultValue { value } else { nil }
        switch kind {
        case .text:
            defaultValue = SwiftUILiteral.string(spelling ?? "")
        case .color:
            let color: PenValue<String>? = spelling.map { $0.hasPrefix("$") ? .variable(String($0.dropFirst())) : .literal($0) }
            if case let .variable(variable)? = color, let token = theme?.tokens[variable], token.type == .color {
                themedDefault = token
                defaultValue = "nil"
                return
            }
            defaultValue = Self.color(color) ?? {
                unemitted.append("the \(definition.name) default \(spelling ?? "colour") (drawn clear)")
                return "Color.clear"
            }()
        case .image:
            defaultValue = spelling.flatMap(Self.image) ?? "Image(systemName: \"photo\")"
        }
    }

    /// The type the struct declares the prop as: the kind's, optional when the default is
    /// the theme's.
    var swiftType: String {
        themedDefault == nil ? kind.swiftType : kind.swiftType + "?"
    }

    /// What the body reads: the prop, or — when it defaults to the theme's colour — the prop
    /// falling back to the theme: `tint ?? theme.accent`.
    var themedRead: String {
        themedDefault.map { "\(name) ?? \($0.read)" } ?? name
    }

    /// The init's parameter: `label: String = "Total"`.
    ///
    /// An image prop's is `image: Image? = nil`, its default applied in the init's body
    /// (``assignment``): the default loads from `Bundle.module`, which SwiftPM declares
    /// internal, and a public init's default argument may not name an internal symbol.
    var parameter: String {
        switch kind {
        case .text, .color: "\(name): \(swiftType) = \(defaultValue)"
        case .image: "\(name): \(kind.swiftType)? = nil"
        }
    }

    /// The init's line that stores the parameter: `self.label = label`.
    var assignment: String {
        switch kind {
        case .text, .color: "        self.\(name) = \(name)"
        case .image: "        self.\(name) = \(name) ?? \(defaultValue)"
        }
    }

    /// `value`, set by an instance's override, as this prop's argument; `nil` when it
    /// cannot be written (a colour variable, a remote image).
    func argument(_ value: PropMapper.Value) -> String? {
        switch (kind, value) {
        case let (.text, .string(text)): SwiftUILiteral.string(text)
        case let (.color, .color(color)): Self.color(color)
        case let (.image, .imageURL(url)): Self.image(url)
        default: nil
        }
    }

    // MARK: - Spellings

    /// A colour the support file's `Color(hex:)` writes, or `nil` for a variable or a
    /// malformed literal.
    private static func color(_ value: PenValue<String>?) -> String? {
        guard case let .literal(hex)? = value, let parsed = PenHexColor(hex) else { return nil }
        return SwiftUILiteral.color(parsed)
    }

    /// The bundled image at `url`, or `nil` when it is not beside the .pen file.
    private static func image(_ url: String) -> String? {
        SwiftUINodeEmitter.resourceName(url).map { "Image(penResource: \(SwiftUILiteral.string($0)), bundle: .module)" }
    }

    /// The kind a prop of `type` has on `node`, or `nil` when the body cannot read it.
    private static func kind(of type: PropType, on node: PenNode) -> Kind? {
        switch (type, node.kind) {
        case (.string, .text): return .text
        case (.color, _), (.imageURL, _):
            guard let fill = boundFill(of: node) else { return nil }
            switch fill {
            case .shorthand, .color: return type == .color ? .color : nil
            case let .image(image): return type == .imageURL && image.url.flatMap(SwiftUINodeEmitter.resourceName) != nil ? .image : nil
            default: return nil
            }
        default: return nil
        }
    }

    /// The index in `fills.all` of the paint a colour or image prop reads — the first
    /// solid colour or image with a URL, as ``ComponentAnalyzer`` infers it.
    static func boundFillIndex(_ fills: PenFills?) -> Int? {
        fills?.all.firstIndex { fill in
            switch fill {
            case .shorthand, .color: true
            case let .image(image): image.url != nil
            default: false
            }
        }
    }

    /// The paint a colour or image prop on `node` reads.
    private static func boundFill(of node: PenNode) -> PenFill? {
        let fills: PenFills? = switch node.kind {
        case let .frame(data): data.fills
        case let .rectangle(data): data.fills
        case let .ellipse(data): data.fills
        case let .text(data): data.fills
        default: nil
        }
        return boundFillIndex(fills).flatMap { fills?.all[$0] }
    }

    /// `name` as a lower-camel-case Swift identifier, back-quoted when it is a keyword.
    static func identifier(_ name: String) -> String {
        let words = name.split { !($0.isLetter || $0.isNumber) || !$0.isASCII }
        var joined = words.enumerated().map { index, word in
            index == 0 ? word.prefix(1).lowercased() + word.dropFirst() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined()
        if joined.isEmpty || joined.first?.isNumber == true {
            joined = "prop" + joined
        }
        if joined == "body" {
            // The view's own `body`.
            joined = "bodyValue"
        }
        return keywords.contains(joined) ? "`\(joined)`" : joined
    }

    /// Swift keywords a prop could be named, which need back quotes as identifiers.
    private static let keywords: Set<String> = [
        "as", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum", "extension",
        "false", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil",
        "operator", "private", "protocol", "public", "repeat", "return", "self", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
    ]
}
