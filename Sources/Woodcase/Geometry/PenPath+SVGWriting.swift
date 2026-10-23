import Foundation

public extension PenPath {
    /// The path as SVG path data that parses back to this path exactly.
    ///
    /// Every command is written absolute — `M`, `L`, `Q`, `C` and `Z` — since the path holds
    /// only resolved commands; relative commands, `H`/`V`, the reflections of `S`/`T` and
    /// arcs were resolved when it was parsed. Every number is written in the shortest form
    /// that reads back as the same `Double`, so for any path parsed with ``init(svg:)``,
    /// `PenPath(svg: path.svgPathData) == path`. Coordinates that are not finite have no SVG
    /// spelling and do not round trip. A path with no commands writes an empty string,
    /// which does not parse.
    ///
    /// ```swift
    /// PenPath(svg: "m10 10 h20 v5 z")!.svgPathData  // "M10 10 L30 10 L30 15 Z"
    /// ```
    var svgPathData: String {
        svgPathData(number: PenSVGPathWriter.exactNumber)
    }

    /// The path as SVG path data, with each number written by `number` — at a fixed precision
    /// for an emitter, say. Only the exact form of ``svgPathData`` is guaranteed to parse back
    /// equal.
    ///
    /// - Parameter number: How a coordinate is written.
    /// - Returns: The commands separated by spaces, e.g. `M0 0 L10 0 Z`.
    func svgPathData(number: (Double) -> String) -> String {
        withoutActuallyEscaping(number) { number in
            var writer = PenSVGPathWriter(number: number)
            for command in commands {
                writer.write(command)
            }
            return writer.pathData
        }
    }
}
