#if os(macOS)
import AppKit

/// MySelf 1.3.1 and earlier used the bundle ID `com.ok9xnirab.myself`, so their data and settings sit in another
/// sandbox container that this app can't open by itself. The user picks that container in an open panel, which
/// grants access, and `AppStore.importLegacyData` copies everything across. The old container is left untouched.
enum LegacyImport {
    static let oldBundleID = "com.ok9xnirab.myself"

    enum Failure: LocalizedError {
        case notFound
        var errorDescription: String? {
            "That folder doesn\u{2019}t hold data from an earlier MySelf. Choose the folder the panel opens on, then click Import."
        }
    }

    /// `~/Library/Containers/com.ok9xnirab.myself`, using the real home folder rather than the sandbox's.
    static var oldContainer: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(filePath: String(cString: home)).appending(path: "Library/Containers/\(oldBundleID)", directoryHint: .isDirectory)
    }

    /// Asks for the old container. Returns nil when cancelled.
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = oldContainer
        panel.prompt = "Import"
        panel.message = "Click Import to bring over the data from the earlier MySelf (com.ok9xnirab.myself). Its copy stays where it is."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Finds the old local data folder and preferences inside whatever part of the container the user picked
    /// (the container itself, its `Data`, `Data/Library`, or the data folder).
    static func locate(in picked: URL) -> (data: URL?, preferences: [String: Any]?) {
        let fm = FileManager.default
        var data: URL?
        var preferences: [String: Any]?
        for base in [picked, picked.appending(path: "Data")] {
            let dataCandidates = ["Library/Application Support/\(oldBundleID)", "Application Support/\(oldBundleID)", oldBundleID, ""]
            for path in dataCandidates where data == nil {
                let url = path.isEmpty ? base : base.appending(path: path, directoryHint: .isDirectory)
                if [Todo.folder, Note.folder].contains(where: { fm.fileExists(atPath: url.appending(path: $0).path) }) { data = url }
            }
            for path in ["Library/Preferences", "Preferences"] where preferences == nil {
                let url = base.appending(path: "\(path)/\(oldBundleID).plist")
                preferences = NSDictionary(contentsOf: url) as? [String: Any]
            }
        }
        return (data, preferences)
    }

    /// Copies the old app's own preferences into this app's UserDefaults. System keys (window frames, AppKit state)
    /// are skipped. When this Mac already has a working sync folder, its sync settings are kept.
    static func apply(_ preferences: [String: Any], keepingSyncFolder: Bool) {
        let systemPrefixes = ["NS", "Apple", "com.apple.", "WebKit", "_"]
        let syncKeys = [SyncEngine.bookmarkKey, PrefKey.iCloudSync, PrefKey.lastSynced]
        let defaults = UserDefaults.standard
        for (key, value) in preferences {
            if systemPrefixes.contains(where: key.hasPrefix) { continue }
            if keepingSyncFolder, syncKeys.contains(key) { continue }
            defaults.set(value, forKey: key)
        }
        if let raw = preferences[SearchShortcut.defaultsKey] as? String {
            SearchShortcut.shared.set(HotKey(rawValue: raw))
        }
    }
}
#endif
