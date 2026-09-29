//
//  SwiftUIAPIUse.swift
//  WoodcaseTests
//

import Woodcase

/// One name a piece of emitted Swift uses that may be an SDK API: a type, a member, a call,
/// a macro or a Core Text constant, as ``SwiftUIAPIScanner`` reads it.
struct SwiftUIAPIUse: Friendly, CustomStringConvertible {
    /// How the name is reached.
    enum Access: String, Friendly {
        /// A bare name: a type (`Color`), a function (`CTFontGetAscent`), a method on
        /// `self` (`overlay`), a constant (`kCTFontNameAttribute`).
        case bare

        /// A member of a value: `view.frame`, `Color.black`, `(x).opacity`.
        case qualified

        /// A member of a type the context implies: `.topLeading`, `.rect(cornerRadius:)`.
        case implicit

        /// A key path: `\.isEnabled`.
        case keyPath

        /// An attribute: `@Environment`, `@Entry`.
        case attribute

        /// A freestanding macro: `#Preview`.
        case macro
    }

    /// The name as written: `frame`, `Color`, `topLeading`.
    var name: String

    /// How the name is reached.
    var access: Access

    /// The argument labels of a call, `_` for an unlabeled one, or `nil` when the name is
    /// not called.
    var labels: [String]?

    /// How many trailing closures follow the call.
    var trailingClosures: Int = 0

    /// The name a qualified member is reached through — `theme` in `theme.brand` — or
    /// `nil` when it is reached through an expression or not qualified.
    var receiver: String?

    /// Whether the name starts with a capital: a type, an initializer call, or a C function.
    var isCapitalized: Bool {
        name.first?.isUppercase ?? false
    }

    /// The use as the tests print it: `.frame(width:height:)`, `ZStack(alignment:{})`,
    /// `\.isEnabled`, `#Preview(_:{})`.
    var description: String {
        let prefix = switch access {
        case .bare: ""
        case .qualified, .implicit: "."
        case .keyPath: "\\."
        case .attribute: "@"
        case .macro: "#"
        }
        guard let labels else { return prefix + name }
        return prefix + name + "(" + labels.map { "\($0):" }.joined() + String(repeating: "{}", count: trailingClosures) + ")"
    }
}
