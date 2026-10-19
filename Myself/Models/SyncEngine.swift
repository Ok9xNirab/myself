import SwiftUI

/// A record stored as its own JSON file, `<folder>/<id>.json`. One file per record means edits to
/// different records on two Macs never conflict, and deleting a record is just removing its file.
protocol SyncRecord: Codable, Identifiable where ID == String {
    static var folder: String { get }
    var updatedAt: Date { get set }
}

/// Appearance and feature visibility, shared through `settings.json` (Settings › iCloud › Also sync).
struct SyncedSettings: Codable, Equatable {
    var appearance: [String: String]?
    var disabledFeatures: [String]?
    var updatedAt = Date.distantPast
}

/// Keeps synced records as files in a folder. With iCloud on, that's a folder the user picked in iCloud Drive
/// (no CloudKit entitlement needed) and iCloud Drive copies it between Macs; otherwise it's Application Support.
///
/// The folder is the source of truth: the store writes every change straight to disk and re-reads the folder
/// when it changes (file presenter), when the app becomes active, and on a slow poll.
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case local, needsFolder, syncing, upToDate
        case failed(String)
    }

    private(set) var status: Status = .local
    private(set) var lastSynced: Date?
    private(set) var isCloudEnabled: Bool
    /// The iCloud Drive folder picked in Settings, kept across launches with a security-scoped bookmark.
    private(set) var cloudFolder: URL?

    /// Called on the main actor whenever the folder may have changed on disk.
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var accessing: URL?
    @ObservationIgnored private var cache: [URL: (modified: Date, record: Any)] = [:]
    @ObservationIgnored private var scanPending = false
    @ObservationIgnored private var scanError: String?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let bookmarkKey = "syncFolderBookmark"
    /// Named after the bundle ID: in unsandboxed builds Application Support is shared with every other app.
    static let localFolder = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "MySelf", directoryHint: .isDirectory)

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    init() {
        let defaults = UserDefaults.standard
        isCloudEnabled = defaults.object(forKey: PrefKey.iCloudSync) as? Bool ?? true
        let last = defaults.double(forKey: PrefKey.lastSynced)
        lastSynced = last > 0 ? Date(timeIntervalSince1970: last) : nil
        cloudFolder = resolveBookmark()
        activate()
        // iCloud Drive doesn't always tell file presenters about remote changes, so poll as a fallback,
        // faster while files are still uploading or downloading.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.scanPending == true ? 5 : 30))
                self?.onChange()
            }
        }
    }

    var usesCloud: Bool { isCloudEnabled && cloudFolder != nil }

    /// Where records live right now.
    var root: URL { usesCloud ? cloudFolder! : Self.localFolder }

    /// True when the picked folder is inside iCloud Drive (any folder works, but only those sync through iCloud).
    var cloudFolderIsInICloud: Bool {
        guard let cloudFolder else { return false }
        let ubiquitous = (try? cloudFolder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
        return ubiquitous || cloudFolder.path.contains("/Library/Mobile Documents/")
    }

    /// "iCloud Drive › MySelf" for folders in iCloud Drive, otherwise the folder path.
    var cloudFolderDisplayName: String? {
        guard let cloudFolder else { return nil }
        let parts = cloudFolder.pathComponents
        if let i = parts.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + parts[(i + 1)...]).joined(separator: " › ")
        }
        return (cloudFolder.path as NSString).abbreviatingWithTildeInPath
    }

    #if os(macOS)
    /// The user's iCloud Drive folder, used as the folder picker's starting point.
    static var iCloudDriveURL: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let url = URL(filePath: String(cString: home)).appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif

    // MARK: Configuration

    func setCloudEnabled(_ on: Bool) {
        isCloudEnabled = on
        UserDefaults.standard.set(on, forKey: PrefKey.iCloudSync)
        activate()
    }

    func useCloudFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try url.bookmarkData(options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        accessing?.stopAccessingSecurityScopedResource()
        accessing = scoped ? url : nil
        cloudFolder = url
        activate()
    }

    #if os(macOS)
    private static let bookmarkOptions: URL.BookmarkCreationOptions = .withSecurityScope
    #else
    private static let bookmarkOptions: URL.BookmarkCreationOptions = []
    #endif

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if url.startAccessingSecurityScopedResource() { accessing = url }
        if stale, let fresh = try? url.bookmarkData(options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Points the watcher at the current root and makes sure its subfolders exist.
    private func activate() {
        watcher?.stop()
        cache = [:]
        let root = root
        for folder in [Todo.folder, TaskLabel.folder, OfficeTask.folder, NoteCategory.folder, Note.folder,
                       UniClass.folder, SyllabusSubject.folder, Assignment.folder, Exam.folder, UniversityNotes.folder] {
            try? FileManager.default.createDirectory(at: root.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        let reload: @MainActor () -> Void = { [weak self] in self?.scheduleReload() }
        watcher = FolderWatcher(url: root) { Task { @MainActor in reload() } }
        updateStatus()
    }

    /// Coalesces bursts of file events into one reload.
    func scheduleReload(after delay: Duration = .milliseconds(300)) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    // MARK: Reading

    /// Wraps a full reload so the status reflects every folder read inside it.
    func scan(_ body: () -> Void) {
        scanPending = false
        scanError = nil
        body()
        updateStatus()
    }

    /// Reads every record in `T.folder`. Records whose file iCloud hasn't downloaded yet keep their `current` value.
    func load<T: SyncRecord>(_ type: T.Type, keeping current: [T]) -> [T] {
        let dir = folderURL(T.self)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
                                         .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys)) else {
            scanError = "Can\u{2019}t read the sync folder."
            return current
        }
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var found: [ID: [(record: T, url: URL)]] = [:]
        var notDownloaded: Set<ID> = []

        for url in urls {
            let name = url.lastPathComponent
            // Older iCloud Drive placeholders: ".<id>.json.icloud"
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let real = dir.appending(path: String(name.dropFirst().dropLast(".icloud".count)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: real)
                notDownloaded.insert(real.deletingPathExtension().lastPathComponent)
                scanPending = true
                continue
            }
            guard url.pathExtension == "json" else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isUbiquitousItem == true {
                if values?.ubiquitousItemIsUploading == true { scanPending = true }
                if let state = values?.ubiquitousItemDownloadingStatus, state != .current {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    notDownloaded.insert(url.deletingPathExtension().lastPathComponent)
                    scanPending = true
                    continue
                }
                if values?.ubiquitousItemHasUnresolvedConflicts == true { resolveConflicts(at: url) }
            }
            let modified = values?.contentModificationDate ?? .distantPast
            if let cached = cache[url], cached.modified == modified, let record = cached.record as? T {
                found[record.id, default: []].append((record, url))
            } else if let record = read(T.self, at: url) {
                cache[url] = (modified, record)
                found[record.id, default: []].append((record, url))
            }
        }

        var records: [T] = []
        for (id, copies) in found {
            // Duplicates such as "<id> 2.json": keep the newest under the canonical name.
            let newest = copies.max { $0.record.updatedAt < $1.record.updatedAt }!
            let canonical = fileURL(T.self, id: id)
            if newest.url != canonical { write(newest.record, to: canonical) }
            for copy in copies where copy.url != canonical { remove(copy.url) }
            records.append(newest.record)
        }
        for id in notDownloaded where found[id] == nil {
            if let record = currentByID[id] { records.append(record) }
        }
        return records
    }

    /// True if `T.folder` holds any file at all, including ones iCloud hasn't downloaded yet.
    func hasFiles<T: SyncRecord>(_ type: T.Type) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folderURL(T.self).path)) ?? []
        return names.contains { $0.hasSuffix(".json") || $0.hasSuffix(".json.icloud") }
    }

    func readSettings() -> SyncedSettings? {
        let url = root.appending(path: "settings.json")
        guard FileManager.default.fileExists(atPath: url.path), isDownloaded(url) else { return nil }
        return read(SyncedSettings.self, at: url)
    }

    // MARK: Writing

    /// Writes `record` to its file. With `onlyIfNewer`, a file that is newer or not yet downloaded is left alone.
    func save<T: SyncRecord>(_ record: T, onlyIfNewer: Bool = false) {
        let url = fileURL(T.self, id: record.id)
        if onlyIfNewer, FileManager.default.fileExists(atPath: url.path) {
            guard isDownloaded(url), let disk = read(T.self, at: url), disk.updatedAt < record.updatedAt else { return }
        }
        write(record, to: url)
    }

    func delete<T: SyncRecord>(_ type: T.Type, id: ID) {
        remove(fileURL(T.self, id: id))
        didWrite()
    }

    func writeSettings(_ settings: SyncedSettings) {
        write(settings, to: root.appending(path: "settings.json"))
    }

    // MARK: Files

    private func folderURL<T: SyncRecord>(_ type: T.Type) -> URL {
        root.appending(path: T.folder, directoryHint: .isDirectory)
    }

    private func fileURL<T: SyncRecord>(_ type: T.Type, id: ID) -> URL {
        folderURL(T.self).appending(path: "\(id).json")
    }

    private func isDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true, let state = values?.ubiquitousItemDownloadingStatus else { return true }
        return state == .current
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        var result: T?
        var error: NSError?
        NSFileCoordinator(filePresenter: watcher).coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = try? decoder.decode(T.self, from: Data(contentsOf: url))
        }
        return result
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        var failure: Error?
        do {
            let data = try encoder.encode(value)
            var error: NSError?
            NSFileCoordinator(filePresenter: watcher).coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
                do { try data.write(to: url, options: .atomic) } catch { failure = error }
            }
            failure = failure ?? error
        } catch {
            failure = error
        }
        if let failure {
            status = .failed(failure.localizedDescription)
        } else {
            didWrite()
        }
    }

    private func remove(_ url: URL) {
        var error: NSError?
        NSFileCoordinator(filePresenter: watcher).coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            try? FileManager.default.removeItem(at: url)
        }
        cache[url] = nil
    }

    /// iCloud Drive keeps losing versions around after a conflict; the newest `updatedAt` already won, so drop them.
    private func resolveConflicts(at url: URL) {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] { version.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    // MARK: Status

    private func didWrite() {
        guard usesCloud else { return }
        scanPending = true
        if status != .needsFolder { status = .syncing }
        // Check back once iCloud Drive has had a moment to pick the change up.
        scheduleReload(after: .seconds(3))
    }

    private func updateStatus() {
        let next: Status
        if !isCloudEnabled {
            next = .local
        } else if cloudFolder == nil {
            next = .needsFolder
        } else if let scanError {
            next = .failed(scanError)
        } else if scanPending {
            next = .syncing
        } else {
            next = .upToDate
            lastSynced = .now
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: PrefKey.lastSynced)
        }
        if next != status { status = next }
    }
}

extension SyncEngine.Status {
    var title: String {
        switch self {
        case .local: "On this Mac only"
        case .needsFolder: "Choose an iCloud folder"
        case .syncing: "Syncing\u{2026}"
        case .upToDate: "Synced with iCloud"
        case .failed: "Sync problem"
        }
    }

    var systemImage: String {
        switch self {
        case .local: "desktopcomputer"
        case .needsFolder, .failed: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "icloud"
        }
    }

    var color: Color {
        switch self {
        case .local: Palette.ink3
        case .needsFolder, .syncing: Palette.amber
        case .upToDate: Palette.green
        case .failed: Palette.red
        }
    }
}

/// Tells the engine when anything inside the sync folder changes. Callbacks arrive on a background queue.
nonisolated private final class FolderWatcher: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }

    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        completionHandler(nil)
        onChange()
    }
}
