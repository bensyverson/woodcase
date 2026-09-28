// The body of scripts/pen-font-audit: compares, family by family, the face Pen draws (its
// bundled Google font table) with the file Woodcase's Google font resolver would pick.
// Compiled by the wrapper together with the library's own selection sources
// (GoogleFontMetadata, its face matching, PenFontFace, GoogleFontCache's directory naming),
// so the choice audited is the one the resolver makes, not a re-implementation of it.
//
// Arguments: <pen-fonts.json> <google-fonts checkout>. Prints one tab-separated row per
// family, then a summary. See scripts/pen-font-audit for usage.

import Foundation

/// One style Pen offers: a file on fonts.gstatic.com at one weight, upright or italic,
/// and the variation axes it spans (none for a static cut).
struct PenStyle: Decodable {
    struct Axis: Decodable, Hashable { let tag: String; let start: Double; let end: Double }
    let url: String
    let weight: Int
    let italic: Bool
    let axes: [Axis]
}

/// A family in Pen's table.
struct PenFamily: Decodable {
    let name: String
    let styles: [PenStyle]
}

/// The ways Woodcase's pick can differ from Pen's file.
enum Disagreement: String, CaseIterable {
    /// No METADATA.pb under the directory name the resolver asks for.
    case notFound = "not-found"
    /// Pen draws a variable file where the resolver picks a static one.
    case staticForVariable = "static-for-variable"
    /// Pen draws a static cut where the resolver picks a variable file.
    case variableForStatic = "variable-for-static"
    /// Pen offers a static weight the resolver answers with another weight.
    case weightSubstituted = "weight-substituted"
    /// Pen offers an italic the resolver answers with an upright file.
    case italicMissing = "italic-missing"
    /// Both are variable, over different axes or ranges.
    case axesDiffer = "axes-differ"
}

/// The `axes { tag: … min_value: … max_value: … }` blocks of a METADATA.pb.
func metadataAxes(_ text: String) -> Set<PenStyle.Axis> {
    let block = /axes\s*\{\s*tag:\s*"(\w{4})"\s*min_value:\s*(-?[\d.]+)\s*max_value:\s*(-?[\d.]+)\s*\}/
    return Set(text.matches(of: block).compactMap { match in
        guard let start = Double(match.2), let end = Double(match.3) else { return nil }
        return PenStyle.Axis(tag: String(match.1), start: start, end: end)
    })
}

/// The gstatic version segment of a URL (`v23`), or `?`.
func version(_ url: String) -> String {
    url.firstMatch(of: /\/(v\d+)\//).map { String($0.1) } ?? "?"
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: pen-font-audit <pen-fonts.json> <google-fonts checkout>\n".utf8))
    exit(64)
}

let families = try JSONDecoder().decode([PenFamily].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let googleFonts = URL(fileURLWithPath: arguments[2], isDirectory: true)
/// The license directories the resolver probes, in its order (`GoogleFontResolver.licenseDirectories`).
let licenseDirectories = ["ofl", "apache", "ufl"]

var counts: [Disagreement: Int] = [:]
var agreements = 0
var variableAgreements = 0
print(["family", "pen kind", "pen version", "pen styles", "pen axes", "woodcase path", "woodcase kind", "woodcase files", "verdict"]
    .joined(separator: "\t"))
for family in families {
    let penVariable = family.styles.contains { !$0.axes.isEmpty }
    let penAxes = Set(family.styles.flatMap(\.axes))
    let penStyles = family.styles.map { "\($0.weight)\($0.italic ? "i" : "")" }.joined(separator: ",")
    let penAxesText = penAxes.sorted { $0.tag < $1.tag }.map { "\($0.tag) \(Int($0.start))-\(Int($0.end))" }.joined(separator: ",")
    let directory = GoogleFontCache.directoryName(for: family.name)
    var row = [family.name, penVariable ? "variable" : "static", version(family.styles[0].url), penStyles, penAxesText]

    let found = licenseDirectories.lazy.compactMap { license -> (String, Data)? in
        let url = googleFonts.appendingPathComponent("\(license)/\(directory)/METADATA.pb")
        return (try? Data(contentsOf: url)).map { ("\(license)/\(directory)", $0) }
    }.first
    guard let (path, data) = found, let metadata = try? GoogleFontMetadata.parse(data) else {
        counts[.notFound, default: 0] += 1
        row += ["-", "-", "-", Disagreement.notFound.rawValue]
        print(row.joined(separator: "\t"))
        continue
    }

    var verdicts: Set<Disagreement> = []
    var picked: [String] = []
    for style in family.styles {
        let face = PenFontFace(family: family.name, weight: style.weight, style: style.italic ? .italic : .normal)
        guard let entry = metadata.entry(weight: face.weight, style: face.style) else { continue }
        picked.append(entry.filename)
        let entryVariable = entry.filename.contains("[")
        if !style.axes.isEmpty, !entryVariable { verdicts.insert(.staticForVariable) }
        if style.axes.isEmpty, entryVariable { verdicts.insert(.variableForStatic) }
        if style.italic, entry.style != PenFontFace.Style.italic.rawValue { verdicts.insert(.italicMissing) }
        if style.axes.isEmpty, !entryVariable, entry.weight != style.weight { verdicts.insert(.weightSubstituted) }
    }
    let axes = metadataAxes(String(decoding: data, as: UTF8.self))
    if penVariable, metadata.isVariable, axes != penAxes { verdicts.insert(.axesDiffer) }

    for verdict in verdicts {
        counts[verdict, default: 0] += 1
    }
    if verdicts.isEmpty {
        agreements += 1
        if penVariable { variableAgreements += 1 }
    }
    let unique = Array(NSOrderedSet(array: picked)) as? [String] ?? picked
    row += [
        path, metadata.isVariable ? "variable" : "static", unique.joined(separator: ","),
        verdicts.isEmpty ? "agrees" : verdicts.map(\.rawValue).sorted().joined(separator: ","),
    ]
    print(row.joined(separator: "\t"))
}

let summary = FileHandle.standardError
func report(_ line: String) {
    summary.write(Data((line + "\n").utf8))
}

report("families in Pen's table: \(families.count) (\(families.count(where: { $0.styles.contains { !$0.axes.isEmpty } })) variable)")
report("agree: \(agreements) (\(variableAgreements) of them variable)")
for kind in Disagreement.allCases {
    report("\(kind.rawValue): \(counts[kind, default: 0])")
}
