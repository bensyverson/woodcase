//
//  HistoryWriter.swift
//  Woodcase
//

import Foundation

#if canImport(SystemConfiguration) && os(macOS)
    import SystemConfiguration
#endif

/// Who appends to one file of a bundle's shared history: an identity on one device.
///
/// A bundle's history is one append-only file per writer (`history/ben@grace.jsonl`),
/// so Git merges and file-sync services never see two writers in one file. A writer is
/// neither a ``PeerID`` — that is per session, and a history outlives sessions — nor the
/// bare identity: one person on two Macs syncing a bundle through Dropbox would then
/// append to one `ben.jsonl` from both and collide. `ben@grace` and `ben@hopper` cannot.
///
/// ```swift
/// let writer = HistoryWriter(identity: "Ben", device: "Grace")
/// writer.rawValue   // "ben@grace"
/// writer.fileName   // "ben@grace.jsonl"
/// ```
///
/// ## A safe file name
///
/// Each half is folded to lowercase ASCII letters, digits, `-` and `_`: accents are
/// stripped, other scripts transliterated (`李` is `li`), and every other run of
/// characters becomes one `-`. So a writer never names a path outside the history
/// directory, never contains the `.` that separates an archive's timestamp
/// (`ben@grace.20260829T163104Z.jsonl`), and is one file on a case-insensitive volume
/// and in a case-sensitive Git tree alike. A half with nothing left — an emoji name — is
/// named by a hash of what it was, so two such identities stay apart. The empty identity
/// is ``ActivityEvent/unattributed``'s writer, `unattributed`. Each half is at most
/// ``maximumLength`` characters.
///
/// The file name is only where rows go: each row keeps the identity exactly as it was
/// given. Two identities that fold to one name on one device share a file, which is
/// safe — appends on one device take the file's lock — and readers still tell them
/// apart by the row.
///
/// ## The device
///
/// A caller names it — an app may use its own setting — or takes ``currentDevice(environment:)``:
/// `$WOODCASE_DEVICE` when set, else this Mac's computer name (System Settings ▸ General
/// ▸ Sharing), which is what a person recognizes in a history and, unlike the network
/// host name, does not change from one network to the next. Two Macs given the same
/// computer name would share a file name; set `$WOODCASE_DEVICE` on one of them.
public struct HistoryWriter: Friendly {
    /// A writer from an identity and a device, each folded to a safe name.
    ///
    /// - Parameters:
    ///   - identity: The writer's `--as` name, or ``ActivityEvent/unattributed``.
    ///   - device: The device's name, from the caller or ``currentDevice(environment:)``.
    public init(identity: String, device: String) {
        self.identity = Self.component(identity, empty: Self.unattributedName)
        self.device = Self.component(device, empty: Self.unnamedDevice)
    }

    /// Reads a writer back from a history file's name without `.jsonl`.
    ///
    /// - Parameter fileStem: `ben@grace`.
    /// - Returns: The writer, or `nil` when the name is not one a writer is filed under —
    ///   an archive's `ben@grace.20260829T163104Z`, a legacy `activity`, or anything not
    ///   already folded.
    public init?(fileStem: String) {
        let parts = fileStem.split(separator: Self.separator, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ Self.isFolded($0) })
        else { return nil }
        identity = String(parts[0])
        device = String(parts[1])
    }

    /// The environment variable that names this device in a writer.
    public static let deviceEnvironmentVariable = "WOODCASE_DEVICE"

    /// The longest either half of a writer may be.
    public static let maximumLength = 64

    /// The identity half, folded.
    public let identity: String

    /// The device half, folded.
    public let device: String

    /// `identity@device`: the file's name without `.jsonl`.
    public var rawValue: String {
        "\(identity)\(Self.separator)\(device)"
    }

    /// The writer's live history file's name: `ben@grace.jsonl`.
    public var fileName: String {
        "\(rawValue).jsonl"
    }

    /// This device's name for a writer: `$WOODCASE_DEVICE` when set and not empty, else
    /// the computer name, else the network host name — folded, as a writer's half is.
    ///
    /// - Parameter environment: The environment to read `$WOODCASE_DEVICE` from.
    /// - Returns: A non-empty, folded name.
    public static func currentDevice(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let named = environment[deviceEnvironmentVariable], !named.isEmpty {
            return component(named, empty: unnamedDevice)
        }
        return component(computerName() ?? hostName(), empty: unnamedDevice)
    }

    // MARK: - Private

    /// What joins the two halves.
    private static let separator: Character = "@"

    /// The identity half of the unattributed writer.
    private static let unattributedName = "unattributed"

    /// The device half when a device's name folds to nothing.
    private static let unnamedDevice = "device"

    /// Folds one half to lowercase ASCII letters, digits, `-` and `_`.
    ///
    /// - Parameters:
    ///   - raw: The name as given.
    ///   - empty: The name for an empty `raw`.
    /// - Returns: The folded half: never empty, at most ``maximumLength`` characters.
    private static func component(_ raw: String, empty: String) -> String {
        guard !raw.isEmpty else { return empty }
        let latin = raw.applyingTransform(.toLatin, reverse: false) ?? raw
        let plain = latin.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var folded = ""
        var pendingDash = false
        for scalar in plain.unicodeScalars {
            if isAllowed(scalar) {
                if pendingDash, !folded.isEmpty { folded.append("-") }
                pendingDash = false
                folded.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        if folded.isEmpty {
            var hasher = FNV1aHasher()
            hasher.combine(raw)
            folded = "w" + hasher.hexString.prefix(8)
        }
        return String(folded.prefix(maximumLength))
    }

    /// Whether a half is already folded: what ``init(fileStem:)`` accepts.
    private static func isFolded(_ part: Substring) -> Bool {
        !part.isEmpty && part.count <= maximumLength && part.unicodeScalars.allSatisfy(isAllowed)
    }

    /// Whether a character survives folding.
    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a" ... "z", "0" ... "9", "-", "_": true
        default: false
        }
    }

    /// This Mac's computer name, or `nil` where there is none to read.
    private static func computerName() -> String? {
        #if canImport(SystemConfiguration) && os(macOS)
            SCDynamicStoreCopyComputerName(nil, nil) as String?
        #else
            nil
        #endif
    }

    /// The network host name without a trailing `.local`.
    private static func hostName() -> String {
        let name = ProcessInfo.processInfo.hostName
        return name.hasSuffix(".local") ? String(name.dropLast(".local".count)) : name
    }
}
