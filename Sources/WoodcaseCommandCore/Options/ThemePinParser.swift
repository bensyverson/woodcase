/// Parses `--theme` flag values like `"mode=dark,platform=ios"` into a dictionary.
enum ThemePinParser {
    enum PinError: Error, CustomStringConvertible {
        case malformedPin(String)

        var description: String {
            switch self {
            case let .malformedPin(pin):
                "Malformed theme pin '\(pin)'. Expected format: axis=value"
            }
        }
    }

    static func parse(_ value: String?) throws -> [String: String] {
        guard let value, !value.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in value.split(separator: ",") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                throw PinError.malformedPin(trimmed)
            }
            let key = String(trimmed[trimmed.startIndex ..< equalsIndex])
            let val = String(trimmed[trimmed.index(after: equalsIndex)...])
            result[key] = val
        }
        return result
    }
}
