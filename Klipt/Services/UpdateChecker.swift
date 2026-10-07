import Foundation

/// A dotted version like `1.6.0`, comparable.
///
/// Every comparison in the updater goes through this. Comparing version
/// strings directly gets "1.10.0" < "1.9.0" wrong, which would strand people
/// on an old build exactly when a release matters most.
struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int, minor: Int, patch: Int

    /// Accepts `1.2.3` or `v1.2.3`, and tolerates a missing patch.
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Drop any pre-release suffix — "1.7.0-beta.1" compares as 1.7.0.
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let parts = core.split(separator: ".").map { Int($0) ?? -1 }
        guard let first = parts.first, first >= 0 else { return nil }
        major = first
        minor = parts.count > 1 && parts[1] >= 0 ? parts[1] : 0
        patch = parts.count > 2 && parts[2] >= 0 ? parts[2] : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

struct AvailableUpdate: Sendable {
    let version: SemanticVersion
    let releaseNotes: String
    let pageURL: URL
    /// Direct link to the .dmg, when the release has one.
    let downloadURL: URL?
}

/// Asks GitHub Releases whether anything newer has shipped.
actor UpdateChecker {
    static let repository = "kianabc/klipt"

    private let session: URLSession
    private let currentVersion: SemanticVersion

    init(session: URLSession = .shared, currentVersion: String? = nil) {
        self.session = session
        let raw = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
        self.currentVersion = SemanticVersion(raw) ?? SemanticVersion("0.0.0")!
    }

    var current: SemanticVersion { currentVersion }

    /// Returns an update only when the published release is strictly newer.
    func check() async throws -> AvailableUpdate? {
        // The list, not `/latest`: someone three versions behind should read
        // what all three did, not only the newest.
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=20")!
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        // 404 just means nothing has been released yet — not worth surfacing.
        guard http.statusCode != 404 else { return nil }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }

        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let newer: [(version: SemanticVersion, json: [String: Any])] = list.compactMap { json in
            guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                  let tag = json["tag_name"] as? String,
                  let version = SemanticVersion(tag), version > currentVersion else { return nil }
            return (version, json)
        }
        .sorted { $0.version > $1.version }

        guard let latest = newer.first else { return nil }
        let json = latest.json
        let notes = Self.combinedNotes(newer.map { ($0.version, $0.json["body"] as? String ?? "") })

        // Both URLs below come from a network response and end up being opened
        // or downloaded. Validate scheme and host rather than trusting them — a
        // `file:` URL in that position would be opened without question.
        let page = (json["html_url"] as? String)
            .flatMap(URL.init(string:))
            .flatMap(Self.trusted)
            ?? URL(string: "https://github.com/\(Self.repository)/releases/latest")!

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
            .flatMap(Self.trusted)

        return AvailableUpdate(version: latest.version, releaseNotes: notes,
                               pageURL: page, downloadURL: dmg)
    }

    /// One block of notes covering every version being skipped, newest first.
    /// Markdown headings are flattened to bold because the alert renders
    /// inline markdown only — a `##` would otherwise show up literally.
    static func combinedNotes(_ releases: [(SemanticVersion, String)]) -> String {
        releases.map { version, body in
            let cleaned = body
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") {
                        let text = trimmed.drop(while: { $0 == "#" })
                            .trimmingCharacters(in: .whitespaces)
                        return text.isEmpty ? "" : "**\(text)**"
                    }
                    if trimmed == "---" { return "" }
                    return String(line)
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "**Klipt \(version)**\n\(cleaned)"
        }
        .joined(separator: "\n\n")
    }

    /// Only https URLs on GitHub's own hosts are ever opened or fetched.
    static func trusted(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return nil
        }
        let allowed = ["github.com", "www.github.com", "objects.githubusercontent.com",
                       "release-assets.githubusercontent.com"]
        return allowed.contains(host) ? url : nil
    }

    enum UpdateError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code): "Could not reach GitHub (HTTP \(code))"
            }
        }
    }
}

enum UpdateFrequency: String, CaseIterable, Sendable {
    case daily
    case weekly

    /// Daily, unlike Murmur's weekly. Klipt's current behaviour is daily, and
    /// quietly halving how often an installed copy hears about a fix would be a
    /// regression dressed up as a new setting.
    static let `default`: UpdateFrequency = .daily

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }
}

enum UpdatePreference {
    private static let autoKey = "app.klipt.checkForUpdates"
    private static let lastKey = "app.klipt.lastUpdateCheck"
    private static let frequencyKey = "app.klipt.updateFrequency"

    static var frequency: UpdateFrequency {
        get {
            guard let raw = UserDefaults.standard.string(forKey: frequencyKey),
                  let value = UpdateFrequency(rawValue: raw) else { return .default }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey) }
    }

    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    static var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: lastKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastKey) }
    }

    /// Daily or weekly, the user's choice.
    ///
    /// Murmur needs an hour of slack here because it ticks once a day: each
    /// tick lands fractionally before the interval is up, finds "not due", and
    /// waits another full day — daily silently becoming every other day. Klipt
    /// ticks hourly, so the next chance is only an hour away and no slack is
    /// needed. Worth knowing if the tick interval is ever lengthened.
    static var isDue: Bool {
        guard automatic else { return false }
        guard let last = lastChecked else { return true }
        return Date().timeIntervalSince(last) > frequency.interval
    }
}
