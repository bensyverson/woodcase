//
//  FigmaPath.swift
//  Woodcase
//

import Foundation

/// An outline as a list of drawing commands: a decoded command stream, or the path a
/// ``FigmaVectorNetwork`` region draws.
///
/// A command stream is what a glyph's `commandsBlob` and a `Path` message's `commandsBlob`
/// name: opcode bytes, each followed by its little-endian `f32` coordinates — 0 close,
/// 1 move, 2 line, 3 quadratic, 4 cubic. See <doc:FigmaClipboard> for the coordinate
/// spaces.
public struct FigmaPath: Friendly {
    /// The commands, in drawing order.
    public var commands: [FigmaPathCommand]

    /// A path of `commands`.
    public init(commands: [FigmaPathCommand] = []) {
        self.commands = commands
    }

    /// Decodes a command stream blob.
    ///
    /// A close with no subpath open is dropped: every glyph stream begins with one, and a
    /// glyph with no outline is nothing else.
    ///
    /// - Throws: ``FigmaBlobError`` for an unknown opcode, a command cut short of its
    ///   coordinates, or a coordinate that is not finite.
    public init(blob: Data) throws(FigmaBlobError) {
        var reader = FigmaBlobReader(blob)
        var commands: [FigmaPathCommand] = []
        var isSubpathOpen = false
        while !reader.isAtEnd {
            let offset = reader.offset
            switch try reader.readByte() {
            case 0:
                if isSubpathOpen { commands.append(.close) }
                isSubpathOpen = false
            case 1:
                try commands.append(.move(to: reader.readPoint()))
                isSubpathOpen = true
            case 2:
                try commands.append(.line(to: reader.readPoint()))
            case 3:
                let control = try reader.readPoint()
                try commands.append(.quadratic(control: control, to: reader.readPoint()))
            case 4:
                let control1 = try reader.readPoint()
                let control2 = try reader.readPoint()
                try commands.append(.cubic(control1: control1, control2: control2, to: reader.readPoint()))
            case let opcode:
                throw .unknownCommand(opcode, offset: offset)
            }
        }
        self.commands = commands
    }

    /// This path with every point, control points included, passed through `transform`.
    public func mapped(_ transform: (FigmaPoint) -> FigmaPoint) -> FigmaPath {
        FigmaPath(commands: commands.map { command in
            switch command {
            case let .move(to): .move(to: transform(to))
            case let .line(to): .line(to: transform(to))
            case let .quadratic(control, to): .quadratic(control: transform(control), to: transform(to))
            case let .cubic(control1, control2, to):
                .cubic(control1: transform(control1), control2: transform(control2), to: transform(to))
            case .close: .close
            }
        })
    }
}
