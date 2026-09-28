//
//  SwiftUIViewCode.swift
//  Woodcase
//

/// One SwiftUI view expression in emitted source: a head (`Rectangle()`,
/// `HStack(spacing: 8)`), an optional view-builder body, and a chain of modifiers.
///
/// The emitter decides *what* each node becomes as a tree of these, and ``lines(indent:)``
/// decides how it is laid out on the page, in Xcode's own style: a modifier after a
/// closing brace sits at the head's indent, one after a plain head is indented a level.
struct SwiftUIViewCode: Friendly {
    /// One modifier call, optionally with a trailing view-builder closure
    /// (`.overlay(alignment: .topLeading) { … }`).
    struct Modifier: Friendly {
        /// The call, with its leading dot: `.frame(width: 80, height: 50)`.
        var call: String

        /// The trailing closure's views, or `nil` for a modifier without one.
        var content: [SwiftUIViewCode]?

        /// A modifier with no trailing closure.
        init(_ call: String) {
            self.call = call
            content = nil
        }

        /// A modifier whose trailing closure builds `content`.
        init(_ call: String, content: [SwiftUIViewCode]) {
            self.call = call
            self.content = content
        }
    }

    /// Comment lines written above the view, without the `// `.
    var comments: [String] = []

    /// The expression that creates the view.
    var head: String

    /// The view-builder body's views, or `nil` when the head takes no closure.
    var body: [SwiftUIViewCode]?

    /// The body closure's parameters (`theme` writes `{ theme in`), or `nil` for none.
    var parameters: String?

    /// The labelled closures after the body's (`} footer: { … }`), empty for most views.
    var trailingClosures: [TrailingClosure] = []

    /// The modifiers, in application order.
    var modifiers: [Modifier] = []

    /// This view with one more modifier.
    func modified(_ call: String) -> SwiftUIViewCode {
        var copy = self
        copy.modifiers.append(Modifier(call))
        return copy
    }

    /// This view with `modifiers` appended, in order.
    func modified(_ modifiers: [Modifier]) -> SwiftUIViewCode {
        var copy = self
        copy.modifiers += modifiers
        return copy
    }

    /// A view whose head takes a view-builder closure of `parameters`:
    /// `PenThemeReader { theme in … }`.
    init(head: String, parameters: String, body: [SwiftUIViewCode]) {
        self.head = head
        self.parameters = parameters
        self.body = body
    }

    /// A view of `head`, with an optional body, comments and modifiers.
    init(comments: [String] = [], head: String, body: [SwiftUIViewCode]? = nil, modifiers: [Modifier] = []) {
        self.comments = comments
        self.head = head
        self.body = body
        self.modifiers = modifiers
    }

    /// The source lines for this view, indented by `indent` levels of four spaces.
    func lines(indent: Int) -> [String] {
        let pad = Self.pad(indent)
        var lines: [String] = comments.map { "\(pad)// \($0)" }
        if let body {
            let open = parameters.map { " { \($0) in" } ?? " {"
            if body.isEmpty, trailingClosures.isEmpty {
                lines.append("\(pad)\(head)\(open)\(parameters == nil ? "" : " ")}")
            } else {
                lines.append("\(pad)\(head)\(open)")
                lines.append(contentsOf: body.flatMap { $0.lines(indent: indent + 1) })
                for closure in trailingClosures {
                    lines.append("\(pad)} \(closure.label): {")
                    lines.append(contentsOf: closure.body.flatMap { $0.lines(indent: indent + 1) })
                }
                lines.append("\(pad)}")
            }
        } else {
            lines.append("\(pad)\(head)")
        }
        let modifierIndent = body == nil ? indent + 1 : indent
        let modifierPad = Self.pad(modifierIndent)
        for modifier in modifiers {
            if let content = modifier.content {
                lines.append("\(modifierPad)\(modifier.call) {")
                lines.append(contentsOf: content.flatMap { $0.lines(indent: modifierIndent + 1) })
                lines.append("\(modifierPad)}")
            } else {
                lines.append("\(modifierPad)\(modifier.call)")
            }
        }
        return lines
    }

    private static func pad(_ indent: Int) -> String {
        String(repeating: "    ", count: indent)
    }
}
