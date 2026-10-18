//
//  CodeLanguage.swift
//  Woodcase
//

/// A language code generation writes, one per emitter.
public enum CodeLanguage: String, Friendly, CaseIterable {
    /// SwiftUI views (``SwiftUIEmitter``).
    case swiftUI

    /// React components styled with Tailwind classes (``ReactEmitter``).
    case react
}
