import Foundation

/// Fits the Gaussian sigma of one blurred step edge, as `scripts/blur-sigma-fit` does.
///
/// A hard edge blurred by a Gaussian of standard deviation σ reads, across one row, as
/// `0.5 · (1 − erf((x + 0.5 − c) / (σ√2)))` once normalised between its two plateaus. The
/// fit is a least-squares grid search over `(c, σ)`, narrowed around the best point, on the
/// encoded sRGB values — the space Pen blurs in.
struct EdgeSigmaFit {
    /// The fitted edge centre, in columns of the sampled range.
    let center: Double
    /// The fitted sigma, in pixels.
    let sigma: Double
    /// The root-mean-square residual of the normalised profile against the model.
    let rms: Double

    /// Fits `profile`, one 0…1 sample per column, averaging `plateauSamples` columns at each
    /// end for the plateaus. Returns `nil` when the two plateaus are equal: there is no edge.
    init?(profile: [Double], plateauSamples: Int = 5) {
        let count = min(plateauSamples, max(1, profile.count / 2))
        let left = profile.prefix(count).reduce(0, +) / Double(count)
        let right = profile.suffix(count).reduce(0, +) / Double(count)
        let low = min(left, right)
        let high = max(left, right)
        guard high - low > 1e-6 else { return nil }
        let target = profile.map { left >= right ? ($0 - low) / (high - low) : (high - $0) / (high - low) }

        func sse(_ c: Double, _ sigma: Double) -> Double {
            target.enumerated().reduce(0) { total, sample in
                let model = 0.5 * (1 - erf((Double(sample.offset) + 0.5 - c) / (sigma * 2.0.squareRoot())))
                return total + (model - sample.element) * (model - sample.element)
            }
        }

        let last = Double(profile.count - 1)
        var cRange = (0.0, last)
        var sRange = (0.05, max(last, 1))
        var best = (c: last / 2, sigma: 1.0, error: Double.infinity)
        let steps = 60
        for _ in 0 ..< 4 {
            for ci in 0 ... steps {
                let c = cRange.0 + (cRange.1 - cRange.0) * Double(ci) / Double(steps)
                for si in 0 ... steps {
                    let sigma = sRange.0 + (sRange.1 - sRange.0) * Double(si) / Double(steps)
                    let error = sse(c, sigma)
                    if error < best.error { best = (c, sigma, error) }
                }
            }
            let cSpan = (cRange.1 - cRange.0) / Double(steps) * 3
            let sSpan = (sRange.1 - sRange.0) / Double(steps) * 3
            cRange = (best.c - cSpan, best.c + cSpan)
            sRange = (max(0.01, best.sigma - sSpan), best.sigma + sSpan)
        }
        center = best.c
        sigma = best.sigma
        rms = (best.error / Double(profile.count)).squareRoot()
    }
}
