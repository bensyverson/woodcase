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

    /// The labeled closures after the body's (`} footer: { … }`), empty for most views.
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
    ///
    /// Laid out from a work list rather than by recursion, so a view nested as deep as
    /// any design costs no stack (issue `g5SACU`). Each level is freed as it is laid out,
    /// its nested views held by the work list, so a tree handed over whole
    /// (``lines(of:indent:)`` with `consume`) is not freed by recursion either.
    consuming func lines(indent: Int) -> [String] {
        Self.lines(of: consume self, indent: indent)
    }

    /// `view`'s source lines, indented by `indent` levels of four spaces
    /// (``lines(indent:)``), taking the view over: a caller that is done with a tree
    /// passes it with `consume`, and the tree is freed level by level as it is laid out.
    static func lines(of view: consuming SwiftUIViewCode, indent: Int) -> [String] {
        var lines: [String] = []
        var pending: [Piece] = [.view(consume view, indent: indent)]
        while let piece = pending.popLast() {
            switch piece {
            case let .line(line):
                lines.append(line)
            case let .view(view, indent):
                pending.append(contentsOf: view.pieces(indent: indent).reversed())
            }
        }
        return lines
    }

    /// A part of a view's layout: a line written as it is, or a nested view to lay out.
    private enum Piece {
        /// A finished line.
        case line(String)

        /// A view, laid out at `indent`.
        case view(SwiftUIViewCode, indent: Int)
    }

    /// This view's own lines, in order, with each nested view — in its body, a trailing
    /// closure or a modifier's closure — standing in for its lines.
    private func pieces(indent: Int) -> [Piece] {
        let pad = Self.pad(indent)
        var pieces: [Piece] = comments.map { .line("\(pad)// \($0)") }
        if let body {
            let open = parameters.map { " { \($0) in" } ?? " {"
            if body.isEmpty, trailingClosures.isEmpty {
                pieces.append(.line("\(pad)\(head)\(open)\(parameters == nil ? "" : " ")}"))
            } else {
                pieces.append(.line("\(pad)\(head)\(open)"))
                pieces += body.map { .view($0, indent: indent + 1) }
                for closure in trailingClosures {
                    pieces.append(.line("\(pad)} \(closure.label): {"))
                    pieces += closure.body.map { .view($0, indent: indent + 1) }
                }
                pieces.append(.line("\(pad)}"))
            }
        } else {
            pieces.append(.line("\(pad)\(head)"))
        }
        let modifierIndent = body == nil ? indent + 1 : indent
        let modifierPad = Self.pad(modifierIndent)
        for modifier in modifiers {
            if let content = modifier.content {
                pieces.append(.line("\(modifierPad)\(modifier.call) {"))
                pieces += content.map { .view($0, indent: modifierIndent + 1) }
                pieces.append(.line("\(modifierPad)}"))
            } else {
                pieces.append(.line("\(modifierPad)\(modifier.call)"))
            }
        }
        return pieces
    }

    private static func pad(_ indent: Int) -> String {
        String(repeating: "    ", count: indent)
    }
}
