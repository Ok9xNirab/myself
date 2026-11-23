import Foundation
import Security
import SwiftData

/// A record type the store keeps. `folder` is where the pre-CloudKit versions kept its JSON files (see `FolderImport`).
protocol SyncRecord: Codable, Identifiable where ID == String {
    static var folder: String { get }
    var updatedAt: Date { get set }
}

/// What the app and the widget extension share: the App Group that holds the SwiftData store, a few settings the
/// widgets need (UserDefaults in the group), and the Darwin notification the extension posts after it changes data.
enum SharedStore {
    #if os(macOS)
    static let appGroup = "CR9Y3LFYH4.com.quorrelapps.myself"
    #else
    static let appGroup = "group.com.quorrelapps.myself"
    #endif

    /// Whether this copy syncs with CloudKit's Production environment: true only for App Store and Developer ID (DMG)
    /// builds. Anything Xcode signs, Debug or Release, syncs with Development, whose records are test data, so it must
    /// never open the real store or write the settings the installed app reads. Read from the containing app's
    /// signature, so the widget extension (which has no iCloud entitlement) gets the same answer as its app.
    nonisolated static let isProduction: Bool = {
        #if os(macOS)
        var app = Bundle.main.bundleURL
        while app.pathExtension != "app", app.pathComponents.count > 1 { app.deleteLastPathComponent() }
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return false }
        return entitlements["com.apple.developer.icloud-container-environment"] as? String == "Production"
        #elseif DEBUG
        return false
        #else
        return true
        #endif
    }()

    /// Non-production builds keep their own file, so their Development data can't mix with the real data. They may
    /// also have a newer schema than the installed app, whose widgets would otherwise migrate the store back over them.
    private static let storeName = isProduction ? "MySelf.store" : "MySelf-Debug.store"

    /// Appended to keys in storage that production and test builds share (App Group defaults, iCloud key-value store).
    nonisolated static func scoped(_ key: String) -> String { isProduction ? key : "\(key).development" }

    /// The store file: in the App Group container, so the widget extension opens the same one. Builds not signed for
    /// the group (unsigned development builds) can't write there and use the app's own Application Support instead.
    static let url: URL = {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory),
           (try? fm.createDirectory(at: group, withIntermediateDirectories: true)) != nil {
            return group.appending(path: storeName)
        }
        let local = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "MySelf", directoryHint: .isDirectory)
        try? fm.createDirectory(at: local, withIntermediateDirectories: true)
        return local.appending(path: storeName)
    }()

    /// Whether the App Group container exists for this process (it doesn't in unsigned builds).
    static var hasGroupContainer: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    /// UserDefaults in the App Group. The app copies the settings widgets need here (`disabledFeatures`).
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    /// The App Group copy of Settings › Features: `Page` raw values that are turned off.
    static let disabledFeaturesKey = scoped("disabledFeatures")

    static var disabledFeatures: Set<String> {
        Set(defaults.stringArray(forKey: disabledFeaturesKey) ?? [])
    }

    /// Describes `cloudSchema`, so a process can tell whether the store was last opened with the schema it has.
    private static var schemaFingerprint: String {
        cloudSchema.entities.map { entity in
            let attributes = entity.attributes.map { "\($0.name)=\($0.valueType)" }
            let relationships = entity.relationships.map { "\($0.name)>\($0.destination)" }
            return "\(entity.name):\((attributes + relationships).sorted().joined(separator: ","))"
        }.sorted().joined(separator: ";")
    }

    private static var openedSchemaKey: String { "openedSchema.\(url.lastPathComponent)" }

    /// Whether the app has opened the store with this process's schema. Opening a store with any other schema migrates
    /// it, so widgets check this first: only the app may migrate, or an old widget could undo the app's upgrade.
    static var isStoreCurrent: Bool {
        defaults.string(forKey: openedSchemaKey) == schemaFingerprint
    }

    /// Called by the app once it has opened the store. True if widgets couldn't read it until now.
    @discardableResult static func markStoreOpened() -> Bool {
        guard !isStoreCurrent else { return false }
        defaults.set(schemaFingerprint, forKey: openedSchemaKey)
        return true
    }

    /// Posted (as a Darwin notification, so it crosses processes) when a widget has written to the store; the app
    /// reloads. Prefixed with the App Group, which the macOS sandbox requires.
    nonisolated static let didChangeNotification = "\(appGroup).storeChanged"

    nonisolated static func postDidChange() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(didChangeNotification as CFString), nil, nil, true)
    }
}

/// Widget kinds, so the app can reload one or all of them.
enum WidgetKind {
    static let week = "MySelfWeek"
    static let focus = "MySelfFocus"
    static let today = "MySelfToday"
    static let nextExam = "MySelfNextExam"
    static let nextClasses = "MySelfNextClasses"
    static let jobStudy = "MySelfJobStudy"
    static let capture = "MySelfCapture"
    static let syllabus = "MySelfSyllabus"
    static let revise = "MySelfRevise"
    static let office = "MySelfOffice"
}

/// `myself://` links that widgets open: `myself://todos`, `myself://notes/new`, …
enum DeepLink: Equatable {
    case dashboard, todos, newTodo, office, university, jobStudy, notes, newNote

    static let scheme = "myself"

    var url: URL {
        let path = switch self {
        case .dashboard: "dashboard"
        case .todos: "todos"
        case .newTodo: "todos/new"
        case .office: "office"
        case .university: "university"
        case .jobStudy: "jobstudy"
        case .notes: "notes"
        case .newNote: "notes/new"
        }
        return URL(string: "\(Self.scheme)://\(path)")!
    }

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let parts = ([url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }.filter { !$0.isEmpty }
        switch (parts.first ?? "dashboard", parts.dropFirst().first) {
        case ("dashboard", _): self = .dashboard
        case ("todos", "new"): self = .newTodo
        case ("todos", _): self = .todos
        case ("office", _): self = .office
        case ("university", _): self = .university
        case ("jobstudy", _): self = .jobStudy
        case ("notes", "new"): self = .newNote
        case ("notes", _): self = .notes
        default: return nil
        }
    }
}
