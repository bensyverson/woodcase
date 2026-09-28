import CoreGraphics
import Foundation
import Woodcase

/// A page a WebView suite built for one board: the HTML on disk and the viewport it is
/// rendered at.
///
/// Built off the main actor, so only the WebKit call itself waits on it.
struct WebViewTestPage: Friendly {
    /// The page's HTML file.
    let url: URL

    /// The viewport, in points.
    let size: CGSize
}
