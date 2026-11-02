import SwiftUI
import SwiftData
import CoreData
import CloudKit

/// Appearance and feature visibility, shared through iCloud key-value storage (Settings › iCloud › Also sync).
struct SyncedSettings: Codable, Equatable {
    var appearance: [String: String]?
    var disabledFeatures: [String]?
    var updatedAt = Date.distantPast
}

/// Keeps the synced records in a SwiftData store that CloudKit mirrors to the user's private iCloud database, so
/// every device signed in to the same Apple Account gets the same data. Settings sync through iCloud key-value storage.
///
/// `AppStore` works with plain structs: it saves them here (`save`, `delete`) and reads them back (`load`) inside
/// `scan`, which starts from a fresh context so changes CloudKit imported are always seen. Records with the same ID
/// (two devices creating the same default label, or importing the same folder) are merged on load: the newest
/// `updatedAt` wins, as it did with files.
@Observable
final class CloudStore {
    enum Status: Equatable {
        case local, noAccount, syncing, upToDate
        case failed(String)
    }

    enum ImageState { case ready(URL), downloading, missing }

    static let containerID = "iCloud.com.quorrelapps.myself"

    private(set) var status: Status = .local
    private(set) var lastSynced: Date?
    /// Settings › iCloud › Sync with iCloud.
    private(set) var isCloudEnabled: Bool
    /// True while the store is mirrored to CloudKit: sync is on and the build is signed for iCloud.
    private(set) var usesCloud = false

    /// Called on the main actor when other devices' changes have arrived.
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private var container: ModelContainer!
    @ObservationIgnored private var context: ModelContext!
    /// Models by record ID, per model type; rebuilt by `scan`.
    @ObservationIgnored private var index: [ObjectIdentifier: [String: any PersistentModel]] = [:]
    @ObservationIgnored private var batching = false
    @ObservationIgnored private var accountAvailable = true
    @ObservationIgnored private var syncError: String?
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let settingsKey = "settings"
    private var keyValueStore: NSUbiquitousKeyValueStore { .default }

    /// Where the store file lives; `storeURL` except in tests.
    @ObservationIgnored private let url: URL

    init() {
        url = Self.storeURL
        let defaults = UserDefaults.standard
        isCloudEnabled = defaults.object(forKey: PrefKey.iCloudSync) as? Bool ?? true
        let last = defaults.double(forKey: PrefKey.lastSynced)
        lastSynced = last > 0 ? Date(timeIntervalSince1970: last) : nil
        openContainer()
        observe()
    }

    #if DEBUG
    /// A local-only store at `url`, for `SelfTest`.
    init(testStoreAt url: URL) {
        self.url = url
        isCloudEnabled = false
        openContainer()
    }
    #endif

    // MARK: Container

    /// The store file, in the App Group container so the widget extension reads the same data (`SharedStore`).
    static var storeURL: URL { SharedStore.url }

    /// Whether this build carries the iCloud entitlement. Unsigned builds (`CODE_SIGNING_ALLOWED=NO`) don't, and
    /// touching CloudKit there would crash, so they run on the local store only.
    static var canUseCloudKit: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
        #else
        return true
        #endif
    }

    private func openContainer() {
        container = nil
        context = nil
        index = [:]
        inFlight = []
        syncError = nil
        let cloud = isCloudEnabled && Self.canUseCloudKit
        func make(_ cloud: Bool) throws -> ModelContainer {
            let configuration = ModelConfiguration("MySelf", schema: cloudSchema, url: url,
                                                   cloudKitDatabase: cloud ? .private(Self.containerID) : .none)
            return try ModelContainer(for: cloudSchema, configurations: configuration)
        }
        do {
            container = try make(cloud)
            usesCloud = cloud
        } catch {
            syncError = error.localizedDescription
            usesCloud = false
            // Keep the app usable: the local store, or memory as a last resort.
            container = (try? make(false))
                ?? (try? ModelContainer(for: cloudSchema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        }
        if isCloudEnabled, !cloud, syncError == nil {
            syncError = "This copy of MySelf isn\u{2019}t signed for iCloud, so changes stay on this device."
        }
        newContext()
        refreshAccountStatus()
        updateStatus()
    }

    private func newContext() {
        context = ModelContext(container)
        context.autosaveEnabled = false
        index = [:]
    }

    func setCloudEnabled(_ on: Bool) {
        guard on != isCloudEnabled else { return }
        save()
        isCloudEnabled = on
        UserDefaults.standard.set(on, forKey: PrefKey.iCloudSync)
        openContainer()
    }

    // MARK: Reading

    /// Wraps a full reload: starts from a fresh context, so it sees everything CloudKit has imported.
    func scan(_ body: () -> Void) {
        save()
        newContext()
        body()
    }

    /// Every record of a type. `current` is unused; it's kept so `AppStore.reloadSynced` reads the same as before.
    func load<T: CloudBacked>(_ type: T.Type, keeping current: [T]) -> [T] {
        fetchAll(T.Model.self).map(T.init)
    }

    func hasRecords<T: CloudBacked>(_ type: T.Type) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<T.Model>())) ?? 0) > 0
    }

    /// The model for a record ID, for resolving relationships.
    func model<M: CloudRecord>(_ type: M.Type, id: String) -> M? {
        let key = ObjectIdentifier(M.self)
        if index[key] == nil { _ = fetchAll(M.self) }
        return index[key]?[id] as? M
    }

    /// Fetches every model of a type, merges copies that share a record ID, and indexes them.
    private func fetchAll<M: CloudRecord>(_ type: M.Type) -> [M] {
        let all = (try? context.fetch(FetchDescriptor<M>())) ?? []
        var byID: [String: M] = [:]
        var merged = false
        for model in all {
            guard let kept = byID[model.recordID] else {
                byID[model.recordID] = model
                continue
            }
            let keepNew = (model.updatedAt, model.copyID) > (kept.updatedAt, kept.copyID)
            let (winner, loser) = keepNew ? (model, kept) : (kept, model)
            winner.absorb(loser)
            context.delete(loser)
            byID[model.recordID] = winner
            merged = true
        }
        index[ObjectIdentifier(M.self)] = byID
        if merged { save() }
        return Array(byID.values)
    }

    // MARK: Writing

    /// Writes a record. With `onlyIfNewer`, a stored copy that is as new or newer is kept.
    func save<T: CloudBacked>(_ record: T, onlyIfNewer: Bool = false) {
        let existing = model(T.Model.self, id: record.id)
        if onlyIfNewer, let existing, existing.updatedAt >= record.updatedAt { return }
        let model = existing ?? insert(T.Model.self, id: record.id)
        record.apply(to: model, in: self)
        model.updatedAt = record.updatedAt
        save()
    }

    func delete<T: CloudBacked>(_ type: T.Type, id: ID) {
        guard let model = model(T.Model.self, id: id) else { return }
        context.delete(model)
        index[ObjectIdentifier(T.Model.self)]?[id] = nil
        save()
    }

    /// Runs many writes with one save at the end (imports, Reset).
    func batch(_ body: () -> Void) {
        let outer = batching
        batching = true
        body()
        batching = outer
        save()
    }

    private func insert<M: CloudRecord>(_ type: M.Type, id: String) -> M {
        let model = M()
        model.recordID = id
        model.copyID = UUID().uuidString
        context.insert(model)
        index[ObjectIdentifier(M.self), default: [:]][id] = model
        return model
    }

    /// Makes a parent's child models (topics) match `items`: updates the ones that exist, inserts new ones, deletes
    /// the rest, and passes each item's position for its `order`.
    func syncChildren<P: PersistentModel, C: ChildRecord, S>(of parent: P, _ children: ReferenceWritableKeyPath<P, [C]?>, to items: [S],
                                                             id: KeyPath<S, String>, make: () -> C, update: (C, S, Double) -> Void) {
        var existing: [String: C] = [:]
        for child in parent[keyPath: children] ?? [] {
            if existing[child.recordID] == nil { existing[child.recordID] = child } else { context.delete(child) }
        }
        var kept: [C] = []
        for (i, item) in items.enumerated() {
            let child = existing.removeValue(forKey: item[keyPath: id]) ?? {
                let child = make()
                child.recordID = item[keyPath: id]
                context.insert(child)
                return child
            }()
            update(child, item, Double(i))
            kept.append(child)
        }
        for child in existing.values { context.delete(child) }
        parent[keyPath: children] = kept
    }

    private func save() {
        guard !batching, let context, context.hasChanges else { return }
        do {
            let widgets = WidgetRefresh.affectsWidgets(context)
            try context.save()
            if widgets { WidgetRefresh.schedule() }
        } catch {
            syncError = error.localizedDescription
            updateStatus()
        }
    }

    // MARK: Settings

    func readSettings() -> SyncedSettings? {
        guard let data = keyValueStore.data(forKey: Self.settingsKey) else { return nil }
        return try? JSONDecoder().decode(SyncedSettings.self, from: data)
    }

    func writeSettings(_ settings: SyncedSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        keyValueStore.set(data, forKey: Self.settingsKey)
    }

    // MARK: Note images

    /// Image data lives in `NoteImageModel` (synced as a CloudKit asset); note blocks refer to it by name. Views get
    /// a file URL from a cache in Caches, written the first time an image is shown.
    private static let imageCache: URL = {
        let url = URL.cachesDirectory.appending(path: "noteimages", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Stores image data under a new name and returns it.
    func saveImage(_ data: Data, ext: String) -> String? {
        saveImage(data, name: "\(newID()).\(ext.isEmpty ? "png" : ext.lowercased())")
    }

    /// Stores image data under a given name; used to put a deleted image back on undo, and by imports.
    @discardableResult
    func saveImage(_ data: Data, name: String) -> String? {
        let model = model(NoteImageModel.self, id: name) ?? insert(NoteImageModel.self, id: name)
        model.data = data
        model.updatedAt = .now
        try? data.write(to: cacheURL(name), options: .atomic)
        save()
        return name
    }

    func hasImage(_ name: String) -> Bool { model(NoteImageModel.self, id: name) != nil }

    /// The image's data, for undo.
    func imageData(_ name: String) -> Data? {
        if let data = try? Data(contentsOf: cacheURL(name)) { return data }
        return model(NoteImageModel.self, id: name).map(\.data)
    }

    func deleteImage(_ name: String) {
        if let model = model(NoteImageModel.self, id: name) {
            context.delete(model)
            index[ObjectIdentifier(NoteImageModel.self)]?[name] = nil
        }
        try? FileManager.default.removeItem(at: cacheURL(name))
        save()
    }

    /// Whether an image can be shown yet. One whose record hasn't arrived from iCloud counts as downloading while
    /// sync is busy.
    func imageState(_ name: String) -> ImageState {
        let url = cacheURL(name)
        if FileManager.default.fileExists(atPath: url.path) { return .ready(url) }
        if let model = model(NoteImageModel.self, id: name), !model.data.isEmpty {
            try? model.data.write(to: url, options: .atomic)
            return .ready(url)
        }
        return usesCloud && status == .syncing ? .downloading : .missing
    }

    private func cacheURL(_ name: String) -> URL {
        Self.imageCache.appending(path: name)
    }

    // MARK: Status

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            MainActor.assumeIsolated { if let event { self?.handle(event) } }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountStatus() }
        })
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        })
        keyValueStore.synchronize()
        // A widget ticked a task or logged a revision: read the store again.
        WidgetRefresh.observeWidgetWrites { [weak self] in self?.scheduleReload(after: .milliseconds(100)) }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard usesCloud else { return }
        if event.endDate == nil {
            inFlight.insert(event.identifier)
        } else {
            inFlight.remove(event.identifier)
            if let error = event.error {
                syncError = Self.message(for: error)
            } else {
                syncError = nil
                if event.type != .setup, let end = event.endDate {
                    lastSynced = end
                    UserDefaults.standard.set(end.timeIntervalSince1970, forKey: PrefKey.lastSynced)
                }
                if event.type == .import {
                    scheduleReload()
                    WidgetRefresh.schedule()
                }
            }
        }
        updateStatus()
    }

    private static func message(for error: Error) -> String {
        switch (error as? CKError)?.code {
        case .quotaExceeded: "Your iCloud storage is full, so changes aren\u{2019}t uploading. Free up space in System Settings \u{203A} Apple Account \u{203A} iCloud."
        case .networkUnavailable, .networkFailure: "Waiting for an internet connection. Changes are saved on this device and upload when you\u{2019}re back online."
        case .notAuthenticated: "Sign in to iCloud in System Settings to sync."
        default: error.localizedDescription
        }
    }

    private func refreshAccountStatus() {
        guard usesCloud else { return }
        Task { [weak self] in
            let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
            guard let self else { return }
            accountAvailable = status == nil || status == .available
            updateStatus()
        }
    }

    /// Coalesces bursts of imports into one reload.
    func scheduleReload(after delay: Duration = .milliseconds(300)) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    private func updateStatus() {
        let next: Status = if !isCloudEnabled {
            .local
        } else if usesCloud, !accountAvailable {
            .noAccount
        } else if let syncError {
            .failed(syncError)
        } else if !inFlight.isEmpty {
            .syncing
        } else {
            .upToDate
        }
        if next != status { status = next }
    }
}

extension CloudStore.Status {
    var title: String {
        switch self {
        case .local: "On this device only"
        case .noAccount: "Not signed in to iCloud"
        case .syncing: "Syncing\u{2026}"
        case .upToDate: "Synced with iCloud"
        case .failed: "Sync problem"
        }
    }

    var systemImage: String {
        switch self {
        case .local: "desktopcomputer"
        case .noAccount, .failed: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "icloud"
        }
    }

    var color: Color {
        switch self {
        case .local: Palette.ink3
        case .noAccount, .syncing: Palette.amber
        case .upToDate: Palette.green
        case .failed: Palette.red
        }
    }
}
