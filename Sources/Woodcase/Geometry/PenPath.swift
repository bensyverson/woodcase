import Foundation

/// A path as a list of resolved drawing commands, independent of any graphics framework.
///
/// This is the parse of a `path` node's SVG `geometry`, before and after it is mapped onto
/// the node's box. The CoreGraphics renderer draws it through `cgPath`; a code emitter can
/// write each ``PenPathCommand`` out as a call on its target's path type.
public struct PenPath: Friendly {
    /// The commands, in drawing order.
    public var commands: [PenPathCommand]

    /// Creates a path from its commands.
    public init(commands: [PenPathCommand]) {
        self.commands = commands
    }
}
