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

    /// The website's latest-release link, which redirects to the newest tag's page (`…/releases/tag/v1.1`). Unlike
    /// the REST API it isn't limited to 60 requests an hour per network, which a shared office connection can use up.
    private static let latestRelease = URL(string: "https://github.com/Ok9xNirab/myself/releases/latest")!
    private static let downloads = "https://github.com/Ok9xNirab/myself/releases/download"
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
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
                showAlert(title: "Couldn\u{2019}t check for updates", message: "You seem to be offline. Check your connection and try again.")
            } catch {
                showAlert(title: "Couldn\u{2019}t check for updates", message: error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.latestRelease)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CheckError.http(status) }
        // The redirect ends on the tag's page; with no release yet it stays on the releases list.
        guard let page = response.url, let tagIndex = page.pathComponents.firstIndex(of: "tag"),
              tagIndex + 1 < page.pathComponents.count else { throw CheckError.noRelease }
        let tag = page.pathComponents[tagIndex + 1]
        lastChecked = .now
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: PrefKey.lastUpdateCheck)
        let version = Self.version(fromTag: tag)
        // `scripts/make-dmg.sh` names the file after the version.
        let download = URL(string: "\(Self.downloads)/\(tag)/MySelf-\(version).dmg")
        return Release(version: version, page: page, download: download)
    }

    enum CheckError: LocalizedError {
        case http(Int), noRelease

        var errorDescription: String? {
            switch self {
            case .http(let status): "GitHub answered with an error (HTTP \(status)). Try again in a few minutes."
            case .noRelease: "There\u{2019}s no published release on GitHub yet."
            }
        }
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

/// "Check for Updates…" in the app menu, under About.
struct CheckForUpdatesCommand: View {
    @State private var checker = UpdateChecker.shared

    var body: some View {
        Button("Check for Updates\u{2026}", action: checker.checkNow)
            .disabled(checker.isChecking)
    }
}
#endif
