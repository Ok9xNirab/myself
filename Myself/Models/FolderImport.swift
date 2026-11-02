import Foundation

/// Reads the folder layout earlier versions synced through (`todos/<id>.json`, `labels/`, … `noteimages/`,
/// `university/notes.json`) into the SwiftData store. The folder is never changed, so it stays as a backup.
///
/// Sources: the app's own local folder (once, automatically), the old `com.ok9xnirab.myself` container
/// (`LegacyImport`), and an iCloud Drive sync folder the user picks in Settings › iCloud. A record already in the
/// store is only replaced by a newer copy, so importing twice, or on two devices, changes nothing.
enum FolderImport {
    struct Result {
        var imported = 0
        /// Files iCloud Drive hadn't downloaded yet; asked for, so importing again shortly picks them up.
        var pending = 0
    }

    /// Where records lived before CloudKit when sync was off or no folder was chosen.
    static let localFolder = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "MySelf", directoryHint: .isDirectory)

    /// True if `root` looks like a MySelf data folder.
    static func isDataFolder(_ root: URL) -> Bool {
        [Todo.folder, Note.folder, TaskLabel.folder].contains { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
    }

    @discardableResult
    static func run(from root: URL, into store: CloudStore) -> Result {
        var result = Result()
        store.batch {
            // Records others point at first, so relationships resolve.
            importRecords(TaskLabel.self, root, store, &result)
            importRecords(NoteCategory.self, root, store, &result)
            importRecords(Product.self, root, store, &result)
            importRecords(Note.self, root, store, &result)
            importRecords(Todo.self, root, store, &result)
            importRecords(OfficeTask.self, root, store, &result)
            importRecords(UniClass.self, root, store, &result)
            importRecords(SyllabusSubject.self, root, store, &result)
            importRecords(Assignment.self, root, store, &result)
            importRecords(Exam.self, root, store, &result)
            importRecords(UniversityNotes.self, root, store, &result)
            importRecords(KanbanCard.self, root, store, &result)
            importRecords(StudySubject.self, root, store, &result)
            importImages(root, store, &result)
        }
        return result
    }

    private static func importRecords<T: CloudBacked>(_ type: T.Type, _ root: URL, _ store: CloudStore, _ result: inout Result) {
        let dir = root.appending(path: T.folder, directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        var newest: [ID: T] = [:]
        for name in names {
            let url = dir.appending(path: name)
            if placeholder(name, in: dir, &result) { continue }
            guard url.pathExtension == "json", !name.hasPrefix("."),
                  let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(T.self, from: data) else { continue }
            // Duplicates such as "<id> 2.json": the newest copy wins.
            if let kept = newest[record.id], kept.updatedAt >= record.updatedAt { continue }
            newest[record.id] = record
        }
        for record in newest.values { store.save(record, onlyIfNewer: true) }
        result.imported += newest.count
    }

    private static func importImages(_ root: URL, _ store: CloudStore, _ result: inout Result) {
        let dir = root.appending(path: "noteimages", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names {
            if placeholder(name, in: dir, &result) { continue }
            guard !name.hasPrefix("."), !store.hasImage(name), let data = try? Data(contentsOf: dir.appending(path: name)) else { continue }
            store.saveImage(data, name: name)
            result.imported += 1
        }
    }

    /// An iCloud Drive placeholder (".<name>.icloud") for a file that isn't downloaded: asks for it and counts it.
    private static func placeholder(_ name: String, in dir: URL, _ result: inout Result) -> Bool {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return false }
        let real = dir.appending(path: String(name.dropFirst().dropLast(".icloud".count)))
        try? FileManager.default.startDownloadingUbiquitousItem(at: real)
        result.pending += 1
        return true
    }
}
