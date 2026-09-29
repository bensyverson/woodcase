//
//  ReactEmitter+ColorOpacity.swift
//  Woodcase
//

extension ReactEmitter {
    /// `color` with its alpha multiplied by `opacity`, as CSS.
    ///
    /// A hex color (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`) becomes `#RRGGBBAA`; anything
    /// else — a `var()` — is mixed with `transparent`, which scales its alpha the same way.
    /// An opacity of 1 or more returns `color` unchanged.
    static func cssColor(_ color: String, opacity: Double) -> String {
        guard opacity < 1 else { return color }
        let opacity = max(opacity, 0)
        guard let channels = hexChannels(color) else {
            return "color-mix(in srgb, \(color) \(cssNumber(opacity * 100, decimals: 2))%, transparent)"
        }
        let alpha = Int((Double(channels[3]) * opacity).rounded())
        return "#" + (channels.prefix(3) + [alpha]).map { hexByte($0) }.joined()
    }

    /// The red, green, blue and alpha bytes of a hex color, or `nil` when it is not one.
    static func hexChannels(_ color: String) -> [Int]? {
        guard color.hasPrefix("#") else { return nil }
        let digits = Array(color.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let pairs: [String] = switch digits.count {
        case 3, 4: digits.map { "\($0)\($0)" }
        case 6, 8: stride(from: 0, to: digits.count, by: 2).map { String(digits[$0 ... $0 + 1]) }
        default: []
        }
        guard !pairs.isEmpty else { return nil }
        let bytes = pairs.compactMap { Int($0, radix: 16) }
        return bytes.count == 4 ? bytes : bytes + [255]
    }

    /// A byte as two uppercase hex digits.
    static func hexByte(_ value: Int) -> String {
        let text = String(min(max(value, 0), 255), radix: 16, uppercase: true)
        return text.count == 1 ? "0" + text : text
    }
}
