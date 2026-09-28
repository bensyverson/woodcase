//
//  EmittedSource.swift
//  WoodcaseTests
//

import Foundation

/// A deliberately small reading of an emitted `.tsx` file.
///
/// The test harness carries React, Babel and Tailwind (`Fixtures/js`) but no TypeScript
/// compiler, so nothing here type-checks the emitted file. What it can do instead is name
/// the identifiers a file *binds* and let a test assert that everything the emitted markup
/// uses is among them — which is the failure that shipped when pages referenced
/// `className` and `style` without declaring either.
enum EmittedSource {
    /// Every name the file binds at module scope: what it imports, and what the exported
    /// function destructures out of its one parameter.
    ///
    /// - Parameter source: The contents of an emitted `.tsx` file.
    /// - Returns: The bound identifiers, unordered.
    static func boundNames(in source: String) -> Set<String> {
        var bound: Set<String> = []
        for match in source.matches(of: /import\s*\{([^}]+)\}\s*from/) {
            for name in String(match.output.1).split(separator: ",") {
                bound.insert(name.trimmingCharacters(in: .whitespaces))
            }
        }
        for match in source.matches(of: /export function \w+\(\{([^}]*)\}/) {
            for name in String(match.output.1).split(separator: ",") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { bound.insert(trimmed) }
            }
        }
        return bound
    }
}
