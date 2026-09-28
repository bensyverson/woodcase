import CoreGraphics

extension PenSnapshotTestHelpers {
    /// ``meanAbsoluteError(between:and:)`` on the shared pool rather than the caller's
    /// actor.
    ///
    /// A WebView suite runs on the main actor, where a diff (about 30 ms at 480×360) holds
    /// up every other render's WebKit callbacks; this runs it beside them instead.
    ///
    /// - Parameters:
    ///   - rendered: The render under test.
    ///   - reference: What it should look like.
    /// - Returns: The MAE, in 8-bit channel steps.
    @concurrent
    static func concurrentMeanAbsoluteError(between rendered: CGImage, and reference: CGImage) async -> Double {
        meanAbsoluteError(between: rendered, and: reference)
    }
}
