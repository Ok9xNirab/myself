#if os(macOS)
import SwiftUI

/// Looks for a newer GitHub release than the running build. MySelf has no auto-updater (it's ad-hoc signed, outside the
/// App Store), so this only tells the user and links the DMG; installing is still dragging it into Applications.
///
/// Checks on launch at most once a day while Settings › General › Check for updates is on, and on demand from
/// MySelf › Check for Updates…. A version the user chose to skip only stops the automatic prompt.
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        var version: String
        var page: URL
        var download: URL?
    }

    private(set) var isChecking = false
    private(set) var lastChecked: Date?

    private static let latestRelease = URL(string: "https://api.github.com/repos/Ok9xNirab/myself/releases/latest")!
    private static let interval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private init() {
        let last = UserDefaults.standard.double(forKey: PrefKey.lastUpdateCheck)
        lastChecked = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    /// Called once at launch; quiet unless there's a version the user hasn't skipped.
    func checkAutomatically() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: PrefKey.checkForUpdates) as? Bool ?? true else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.interval { return }
        Task {
            guard let release = try? await fetchLatest(), Self.isNewer(release.version, than: Self.currentVersion),
                  release.version != defaults.string(forKey: PrefKey.skippedVersion) else { return }
            prompt(for: release, allowsSkip: true)
        }
    }

    /// MySelf › Check for Updates…: always reports the result, including "up to date" and errors.
    func checkNow() {
        guard !isChecking else { return }
        Task {
            do {
                let release = try await fetchLatest()
                if Self.isNewer(release.version, than: Self.currentVersion) {
                    prompt(for: release, allowsSkip: false)
                } else {
                    showAlert(title: "You\u{2019}re up to date",
                              message: "\(AppInfo.name) \(Self.currentVersion) is the newest version.")
                }
            } catch {
                showAlert(title: "Couldn\u{2019}t check for updates", message: error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
        lastChecked = .now
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: PrefKey.lastUpdateCheck)
        let dmg = latest.assets.first { $0.name.hasSuffix(".dmg") }
        return Release(version: Self.version(fromTag: latest.tagName), page: latest.htmlURL, download: dmg?.browserDownloadURL)
    }

    private func prompt(for release: Release, allowsSkip: Bool) {
        let alert = NSAlert()
        alert.icon = AppInfo.icon
        alert.messageText = "\(AppInfo.name) \(release.version) is available"
        alert.informativeText = "You have \(Self.currentVersion). Download the new version, quit \(AppInfo.name), and drag it into Applications to replace this one. Your data stays where it is."
        alert.addButton(withTitle: release.download == nil ? "View Release" : "Download")
        alert.addButton(withTitle: "Release Notes")
        if allowsSkip { alert.addButton(withTitle: "Skip This Version") }
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.download ?? release.page)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        case .alertThirdButtonReturn where allowsSkip: UserDefaults.standard.set(release.version, forKey: PrefKey.skippedVersion)
        default: break
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.icon = AppInfo.icon
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    /// "v1.2" → "1.2".
    private static func version(fromTag tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Compares dotted versions numerically, so 1.10 is newer than 1.9 and 1.0 equals 1.0.0.
    static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

nonisolated private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var htmlURL: URL
    var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

/// "Check for Updates…" in the app menu, under About.
struct CheckForUpdatesCommand: View {
    @State private var checker = UpdateChecker.shared

    var body: some View {
        Button("Check for Updates\u{2026}", action: checker.checkNow)
            .disabled(checker.isChecking)
    }
}
#endif
