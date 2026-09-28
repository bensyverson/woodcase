//
//  ThemeOption.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

/// The `--theme <axis=option,…>` option group every verb that resolves variables
/// includes.
///
/// A flag that means one thing on one verb has to mean the same on all of them, and
/// `--theme` was drifting: three verbs spelled the same pin three different ways in
/// their help. One declaration is what keeps them honest, and it is also the one place
/// to change when the pin grammar grows.
///
/// The value is parsed by ``ThemePinParser``, which refuses a malformed pin as a usage
/// error rather than silently rendering the default theme.
///
/// ```swift
/// @OptionGroup var themePin: ThemeOption
/// // …
/// let pins = try ThemePinParser.parse(themePin.theme)
/// ```
struct ThemeOption: ParsableArguments {
    /// The pin as typed, or `nil` for the document's default theme.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Pin theme axes before variables resolve, e.g. \"mode=dark,platform=web\".",
            valueName: "axis=option,…"
        )
    )
    var theme: String?
}
