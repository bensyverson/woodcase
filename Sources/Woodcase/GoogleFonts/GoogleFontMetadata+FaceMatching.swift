//
//  GoogleFontMetadata+FaceMatching.swift
//  Woodcase
//

/// Which of a family's files serves a face, by CSS font matching.
public extension GoogleFontMetadata {
    /// The entry whose file draws `weight` in `style`, as a browser picks it
    /// ([CSS Fonts 4, §5.2](https://www.w3.org/TR/css-fonts-4/#font-style-matching)):
    /// style first — an italic face asked for is taken from the italic entries, and
    /// from the upright ones only when the family has no italic — then weight.
    ///
    /// A weight the family ships is its own entry. Otherwise, above 500 the next heavier
    /// entry is taken and then the next lighter; below 400 the next lighter and then the
    /// next heavier; from 400 to 500 the heavier ones up to 500 and then the lighter. A
    /// variable family lists one entry per file, so every weight lands on its style's
    /// file.
    ///
    /// - Parameters:
    ///   - weight: The CSS weight, 100 to 900.
    ///   - style: Upright or italic.
    /// - Returns: The entry, or `nil` when the metadata lists no fonts at all.
    func entry(weight: Int, style: PenFontFace.Style) -> FontEntry? {
        let styled = fonts.filter { $0.style == style.rawValue }
        let candidates = styled.isEmpty ? fonts.filter { $0.style != style.rawValue } : styled
        if let exact = candidates.first(where: { $0.weight == weight }) { return exact }
        let lighter = candidates.filter { $0.weight < weight }.sorted { $0.weight > $1.weight }
        let heavier = candidates.filter { $0.weight > weight }.sorted { $0.weight < $1.weight }
        switch weight {
        case ..<400:
            return lighter.first ?? heavier.first
        case 400 ... 500:
            return heavier.first { $0.weight <= 500 } ?? lighter.first ?? heavier.first
        default:
            return heavier.first ?? lighter.first
        }
    }
}
