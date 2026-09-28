//
//  ShotCrop.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// The `--crop x,y,w,h` argument: a sub-rectangle of the node being shot, written in
/// the node's own layout points.
///
/// A vision model has an edge limit, and a board taller than that limit shrunk whole to
/// fit it is a picture of nothing. The way out is to tile, and a tile is a crop — so
/// `--crop` is measured in exactly the space the printed `rect=` establishes, `--max`
/// and `--scale` then size the *crop* rather than the node, and the crop's own origin
/// becomes the `rect=` of the run. One coordinate space, one mapping formula, whether or
/// not a crop was asked for.
///
/// Parsing is deferred the way ``PenFilePath``'s is, but for the opposite reason: the
/// shape of `x,y,w,h` really is a question about the invocation, so ``region()`` throws
/// `ValidationError` (exit 2) — it is deferred only so the message can name what was
/// wrong instead of ArgumentParser's generic "invalid value".
struct ShotCrop: ExpressibleByArgument, Friendly, CustomStringConvertible {
    /// Wraps the argument as typed.
    ///
    /// - Parameter text: The `--crop` value, unparsed.
    init(_ text: String) {
        self.text = text
    }

    /// Wraps an argument. Never fails — see ``region()``.
    ///
    /// - Parameter argument: The `--crop` value as typed.
    init?(argument: String) {
        self.init(argument)
    }

    /// The value as typed.
    let text: String

    /// The value as typed, for a message.
    var description: String {
        text
    }

    /// The rectangle the caller asked for.
    ///
    /// - Returns: The crop, in the rendered node's own coordinate space.
    /// - Throws: `ValidationError` when the value is not four numbers, or when its
    ///   width or height would render no pixels.
    func region() throws -> PenRect {
        let fields = text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let numbers = fields.compactMap(Double.init)
        guard fields.count == 4, numbers.count == 4 else {
            throw ValidationError("""
            --crop takes four numbers, x,y,w,h, in the node's own layout points — got \
            '\(text)'. `woodcase shot <file> <node> --out <path> --json` prints the \
            node's rect, which is the space to crop inside.
            """)
        }
        guard numbers[2] > 0, numbers[3] > 0 else {
            throw ValidationError("""
            --crop needs a positive width and height, got \(numbers[2]) by \(numbers[3]) \
            — a crop with no area renders no pixels. Write it as x,y,w,h, not as two \
            corners.
            """)
        }
        return PenRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// A rect written the way `--crop` accepts it, so a refusal can hand back a command
    /// the caller can paste.
    ///
    /// - Parameter rect: The rect to spell.
    /// - Returns: `x,y,w,h` at full `Double` precision, matching the `rect=` field.
    static func argument(for rect: PenRect) -> String {
        "\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
    }
}
