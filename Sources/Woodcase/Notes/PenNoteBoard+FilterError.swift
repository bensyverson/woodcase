//
//  PenNoteBoard+FilterError.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// Why a filter value was refused.
    enum FilterError: Error, Friendly {
        /// An identity filter named someone close to, but not exactly, an identity the
        /// file holds — a typo that would otherwise list nothing and read as "no work".
        ///
        /// - Parameters:
        ///   - option: The flag, such as `--mentions`.
        ///   - value: The value given.
        ///   - suggestion: The identity most likely meant.
        ///   - known: Every identity the file names, sorted.
        case misspelledIdentity(option: String, value: String, suggestion: String, known: [String])

        /// The refusal as one message: what was refused, the one meant, the valid
        /// choices, and the command to run instead.
        public var message: String {
            switch self {
            case let .misspelledIdentity(option, value, suggestion, known):
                "\(option) \(value) names no one in this file — did you mean `\(option) \(suggestion)`? "
                    + "The file names: \(known.joined(separator: ", ")). Identities match exactly, case included."
            }
        }
    }
}
