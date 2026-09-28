//
//  EdgeLengths+CSS.swift
//  Woodcase
//

extension EdgeLengths {
    /// The sides as a CSS shorthand value: one length when uniform, else four in CSS order.
    var css: String {
        isUniform ? top.css : all.map(\.css).joined(separator: " ")
    }
}
