//
//  String+GraphemeBoundaries.swift
//  Woodcase
//

import Foundation

extension String {
    /// The UTF-16 offset of every grapheme-cluster boundary, 0 and the length included, in
    /// order: the places a caret may stand and a run may begin or end.
    var graphemeBoundariesInUTF16: [Int] {
        var offset = 0
        var boundaries = [0]
        for character in self {
            offset += character.utf16.count
            boundaries.append(offset)
        }
        return boundaries
    }
}
