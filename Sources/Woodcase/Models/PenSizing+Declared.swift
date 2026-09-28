//
//  PenSizing+Declared.swift
//  Woodcase
//

import Foundation

public extension PenSizing {
    /// The sizing a raw .pen value declares, or `nil` if it declares none.
    ///
    /// This is how a node of a type this build does not model is sized: its `width` and
    /// `height` are kept as raw ``AnyCodable`` properties, and the layout engine reads them
    /// back through here, so a newer Pen's node still occupies the box Pen gave it.
    ///
    /// ```swift
    /// PenSizing(declared: 200)                 // .fixed(200)
    /// PenSizing(declared: "fill_container")    // .fillContainer(fallback: nil)
    /// PenSizing(declared: nil)                 // nil
    /// ```
    ///
    /// - Parameter value: A number, a sizing keyword, a `$variable`, or `nil`.
    init?(declared value: AnyCodable?) {
        switch value {
        case let .int(number):
            self = .fixed(Double(number))
        case let .double(number):
            self = .fixed(number)
        case let .string(text):
            guard let sizing = try? JSONDecoder().decode(PenSizing.self, from: JSONEncoder().encode(text)) else {
                return nil
            }
            self = sizing
        default:
            return nil
        }
    }
}
