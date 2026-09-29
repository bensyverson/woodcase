//
//  SwiftUIViewCode+TrailingClosure.swift
//  Woodcase
//

extension SwiftUIViewCode {
    /// A labeled trailing closure written after the body's: `} footer: { … }`, as a call
    /// that fills a component's second slot ends.
    struct TrailingClosure: Friendly {
        /// The argument label: `footer`.
        var label: String

        /// The closure's views.
        var body: [SwiftUIViewCode]
    }
}
