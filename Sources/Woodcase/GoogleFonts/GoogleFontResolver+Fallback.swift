//
//  GoogleFontResolver+Fallback.swift
//  Woodcase
//

import Foundation

/// What to say about a family that could not be placed, and where that gets said.
extension GoogleFontResolver {
    /// What to say about a family this machine could not place — one of two sentences.
    ///
    /// "Not in the cache" and "the cache cannot be read" are different facts with
    /// different remedies, and one sentence used to cover both. A reader inside an agent
    /// sandbox, whose allowlist did not name the cache directory, followed the advice to
    /// run `shot`, saw the identical line again, and had no path to check — an hour, in
    /// the trial of 2026-09-08. So the unreadable case says so and stops: a download
    /// would land in the same directory the process cannot read.
    ///
    /// Both name the cache root, because a caller who wants to check it — or to move it
    /// with `$WOODCASE_HOME` — needs to know which directory is meant.
    ///
    /// - Parameter family: The family that could not be placed.
    /// - Returns: The message, without a leading `woodcase: `.
    func fallbackMessage(for family: String) -> String {
        let path = cache.rootDirectory.path
        let fallback = PenTextMeasurer.defaultFontFamily
        guard !cacheIsUnreadable else {
            return "font \"\(family)\" is not installed, and the font cache at \(path) "
                + "exists but cannot be read, so the fonts in it are not used; "
                + "text in it is measured in \(fallback)."
        }
        return "font \"\(family)\" is not installed and not in the font cache at \(path); "
            + "text in it is measured in \(fallback). "
            + "Run `woodcase render` or `woodcase shot` once to download it there."
    }

    /// Whether the cache root is a directory this process cannot read.
    ///
    /// A cache that is simply absent is not unreadable — that is the ordinary
    /// never-downloaded case, and the first write creates it. This is the other one: a
    /// directory that is right there, holding who knows what, behind permissions.
    private var cacheIsUnreadable: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: cache.rootDirectory.path, isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }
        return !FileManager.default.isReadableFile(atPath: cache.rootDirectory.path)
    }

    /// Says, once per family, that text in `family` will be measured and drawn in the
    /// fallback face.
    ///
    /// One rule for every verb: the warning goes to the collector when there is one,
    /// and to standard error when there is not. Never both — a caller holding a
    /// collector has its own place and moment to print, and a second copy on standard
    /// error would be a duplicate it cannot suppress. `shot`, which passes no
    /// collector, is the reason the standard-error half exists.
    ///
    /// - Parameters:
    ///   - family: The family that could not be resolved.
    ///   - message: What to say about it, without a leading `woodcase: `.
    ///   - diagnostics: The collector to report to, or `nil` for standard error.
    func reportFallback(
        family: String,
        message: String,
        diagnostics: PenDiagnosticCollector?
    ) {
        if let diagnostics {
            diagnostics.warn(message, stage: .fontResolution)
            return
        }
        let shouldLog = state.withLock { $0.reportedFallbacks.insert(family).inserted }
        guard shouldLog else { return }
        StandardErrorLine.write("woodcase: \(message)")
    }

    /// What to say about a family that ``resolve(_:)`` could not download.
    ///
    /// Three facts with three remedies: the repository has no such family (fix the
    /// name), the download could not happen (fix the network — the reason says how), or
    /// something else went wrong after the metadata arrived.
    ///
    /// - Parameter family: The family that stays unresolved.
    /// - Returns: The message, without a leading `woodcase: `.
    func downloadFailureMessage(for family: String) -> String {
        let fallback = PenTextMeasurer.defaultFontFamily
        switch state.withLock({ $0.downloadFailures[family] }) {
        case .familyNotFound:
            return "font \"\(family)\" is not installed, and Google Fonts has no family named "
                + "\"\(family)\"; text in it falls back to \(fallback)."
        case let .networkUnavailable(_, failure):
            return "font \"\(family)\" is not installed and could not be downloaded from Google Fonts: "
                + "\(failure.reasonPhrase); text in it falls back to \(fallback)."
        case .metadataParseError, .weightNotAvailable, nil:
            return "Font '\(family)' could not be resolved; will fall back to \(fallback)"
        }
    }
}
