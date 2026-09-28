//
//  ReactEmitter+ConicGradientCSS.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// How many equal turns a bent angular gradient is sampled at, besides its own stops.
    static let conicSamples = 90

    /// An angular gradient at Pen's geometry, as a `conic-gradient` about Pen's centre.
    ///
    /// Pen measures the turn in the gradient's own space and then stretches it to the box
    /// (``GradientGeometry/angularBearing(atTurn:width:height:)``). Where that map keeps
    /// angles — a square box and an even `size` — the turns are the bearings, started
    /// `from` Pen's turn 0. Elsewhere the stretch bends them, which a conic gradient cannot
    /// express, so the gradient is sampled at its stops and ``conicSamples`` equal turns,
    /// each placed at its bearing with the colour Pen's ramp has there; CSS interpolates
    /// linearly between neighbours. A box with a side that is not fixed counts as square.
    static func cssConicGradient(
        _ geometry: GradientGeometry,
        stops: GradientStops,
        box: FillBox,
        outsets: EdgeLengths
    ) -> CSSGradient {
        // One fixed side says nothing about the proportions, so only a fully fixed box bends.
        let (width, height) = if let width = box.width, let height = box.height, width > 0, height > 0 {
            (width, height)
        } else {
            (1.0, 1.0)
        }
        let start = geometry.angularBearing(atTurn: 0, width: width, height: height)
        let at = gradientCentre(geometry.center, outsets: outsets)
        let list: [String] = if geometry.keepsAngles(width: width, height: height) {
            stops.map { "\($0.color) \(cssPercent($0.position))" }
        } else {
            bentConicStops(geometry, stops: stops, start: start, width: width, height: height)
        }
        let from = start == 0 ? "" : "from \(cssNumber(start, decimals: 3))deg"
        let header = from.isEmpty && at.isEmpty ? "" : "\(from.isEmpty ? "from 0deg" : from)\(at), "
        return CSSGradient(image: "conic-gradient(\(header)\(list.joined(separator: ", ")))")
    }

    /// The stops of an angular gradient on a stretched box: each of Pen's stops and each
    /// sampled turn at its bearing past `start`, in bearing order. A mirrored map sweeps
    /// its turns counter-clockwise on screen, so their bearings count down from a full turn.
    private static func bentConicStops(
        _ geometry: GradientGeometry,
        stops: GradientStops,
        start: Double,
        width: Double,
        height: Double
    ) -> [String] {
        let m = geometry.affineComponents
        let clockwise = width * m.a * height * m.d - height * m.b * width * m.c > 0
        var samples: [(turn: Double, color: String)] = stops
            .filter { $0.position >= 0 && $0.position <= 1 }
            .map { ($0.position, $0.color) }
        for index in 0 ... conicSamples {
            let turn = Double(index) / Double(conicSamples)
            guard !stops.contains(where: { $0.position == turn }) else { continue }
            samples.append((turn, colorOnRamp(stops, at: turn)))
        }
        let placed = samples.map { sample -> (bearing: Double, turn: Double, color: String) in
            let bearing = geometry.angularBearing(atTurn: sample.turn, width: width, height: height)
            var swept = ((clockwise ? bearing - start : start - bearing).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            if sample.turn >= 1 || (sample.turn > 0.5 && swept < 1e-9) { swept = 360 }
            return (clockwise ? swept : 360 - swept, sample.turn, sample.color)
        }
        return placed
            .sorted { ($0.bearing, clockwise ? $0.turn : -$0.turn) < ($1.bearing, clockwise ? $1.turn : -$1.turn) }
            .map { "\($0.color) \(cssNumber($0.bearing, decimals: 3))deg" }
    }

    /// The colour of Pen's ramp at `position`: the end colours past the first and last
    /// stops, as Pen pads them, and between two stops their mix, channel by channel as
    /// the renderer interpolates — or `color-mix()` when a colour is not a hex literal.
    static func colorOnRamp(_ stops: GradientStops, at position: Double) -> String {
        guard let first = stops.first, let last = stops.last else { return "transparent" }
        if position <= first.position { return first.color }
        if position >= last.position { return last.color }
        guard let upper = stops.firstIndex(where: { $0.position >= position }), upper > 0 else { return first.color }
        let lower = stops[upper - 1]
        let span = stops[upper].position - lower.position
        let weight = span > 0 ? (position - lower.position) / span : 0
        guard let from = hexChannels(lower.color), let to = hexChannels(stops[upper].color) else {
            let share = cssNumber((1 - weight) * 100, decimals: 2)
            return "color-mix(in srgb, \(lower.color) \(share)%, \(stops[upper].color))"
        }
        let mixed = zip(from, to).map { Int((Double($0) + (Double($1) - Double($0)) * weight).rounded()) }
        let channels = mixed[3] == 255 ? Array(mixed.prefix(3)) : mixed
        return "#" + channels.map { hexByte($0) }.joined()
    }
}
