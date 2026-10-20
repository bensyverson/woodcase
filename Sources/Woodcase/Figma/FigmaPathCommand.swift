//
//  FigmaPathCommand.swift
//  Woodcase
//

/// One drawing command of a ``FigmaPath``, in absolute coordinates.
public enum FigmaPathCommand: Friendly {
    /// Starts a subpath at `to`.
    case move(to: FigmaPoint)
    /// A straight line from the current point to `to`.
    case line(to: FigmaPoint)
    /// A quadratic Bézier curve from the current point to `to`.
    case quadratic(control: FigmaPoint, to: FigmaPoint)
    /// A cubic Bézier curve from the current point to `to`.
    case cubic(control1: FigmaPoint, control2: FigmaPoint, to: FigmaPoint)
    /// Closes the current subpath with a line back to its start.
    case close
}
