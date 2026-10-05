//
//  RecordingTextMeasurer.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Woodcase

/// A deterministic text measurer that records every string it was asked to measure.
///
/// Give each board's texts a string no other board holds and the record says which
/// boards a layout pass actually walked: a board whose texts were never measured was
/// not laid out. Sizes are a fixed 7 points a character and 16 points a line, wrapped
/// at the offered width, so a layout never depends on the fonts installed.
final class RecordingTextMeasurer: Sendable {
    /// The strings measured since the last ``reset()``.
    private let recorded = Mutex<Set<String>>([])

    /// Points per character.
    static let characterWidth: Double = 7

    /// Points per line.
    static let lineHeight: Double = 16

    /// The strings measured since the last ``reset()``.
    var texts: Set<String> {
        recorded.withLock { $0 }
    }

    /// Forgets every string measured so far.
    func reset() {
        recorded.withLock { $0.removeAll() }
    }

    /// The measurer to hand the layout engine.
    var measurer: TextMeasurer {
        { [self] text, _, _, _, _, _, _, maxWidth in
            recorded.withLock { _ = $0.insert(text) }
            let natural = Double(text.count) * Self.characterWidth
            guard let maxWidth, maxWidth > 0, natural > maxWidth else {
                return (natural, Self.lineHeight)
            }
            return (maxWidth, (natural / maxWidth).rounded(.up) * Self.lineHeight)
        }
    }
}
