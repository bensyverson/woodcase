//
//  PasteNames.swift
//  Woodcase
//

import Foundation

/// The names a paste gives a component or a variable whose name the target already holds.
///
/// A component is numbered after a space, as a designer numbers a copy: `Button` →
/// `Button 2`, and `Button 2` → `Button 3`. A variable is numbered after a hyphen, because
/// its name is written into values as `$name` and a space would read as two words:
/// `primary` → `primary-2`. A name that already ends in a number counts on from it, and
/// the first number nothing holds wins.
enum PasteNames {
    /// A component name nothing in `taken` holds.
    ///
    /// - Parameters:
    ///   - name: The name the clip carried.
    ///   - taken: Every name already spoken for.
    /// - Returns: `name` numbered from 2, or on from its own number.
    static func component(_ name: String, avoiding taken: Set<String>) -> String {
        numbered(name, separator: " ", avoiding: taken)
    }

    /// A variable name nothing in `taken` holds.
    ///
    /// - Parameters:
    ///   - name: The name the clip carried.
    ///   - taken: Every name already spoken for.
    /// - Returns: `name` numbered from 2, or on from its own number.
    static func variable(_ name: String, avoiding taken: Set<String>) -> String {
        numbered(name, separator: "-", avoiding: taken)
    }

    /// A name numbered after a separator, the first such that `taken` does not hold.
    ///
    /// - Parameters:
    ///   - name: The name to number.
    ///   - separator: What goes between the name and its number.
    ///   - taken: Every name already spoken for.
    /// - Returns: The numbered name.
    private static func numbered(_ name: String, separator: String, avoiding taken: Set<String>) -> String {
        var base = name
        var number = 2
        if let index = name.range(of: separator, options: .backwards),
           let existing = Int(name[index.upperBound...]), existing >= 1
        {
            base = String(name[..<index.lowerBound])
            number = existing + 1
        }
        while taken.contains("\(base)\(separator)\(number)") {
            number += 1
        }
        return "\(base)\(separator)\(number)"
    }
}
