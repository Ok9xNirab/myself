import Foundation

/// Every SF Symbol on this system, for the note icon picker: names in the SF Symbols app's order, their search
/// keywords and categories, read from the system's CoreGlyphs bundle (plain plists, no private API). Localized
/// variants (`.ar`, `.hi`, `.ja`, …) are left out. Empty when the bundle can't be read; the picker then offers
/// `NoteIcon.symbols`.
struct SymbolCatalog: Sendable {
    struct Category: Identifiable, Sendable {
        let id: String
        let title: String
        let icon: String
    }

    var names: [String] = []
    var keywords: [String: [String]] = [:]
    var categories: [Category] = []
    var membership: [String: Set<String>] = [:]

    /// Loaded once, off the main thread.
    nonisolated static func load() async -> SymbolCatalog {
        await cache.value
    }

    private nonisolated static let cache = Task.detached(priority: .userInitiated) { read() }

    private nonisolated static let directory = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// Script and locale suffixes the system adds for localized glyphs.
    private nonisolated static let localeSuffixes: Set<String> = [
        "ar", "hi", "rtl", "he", "ja", "th", "zh", "bn", "gu", "kn", "ko", "ml", "mni", "mr", "or", "pa", "sat", "te",
        "si", "ta", "el", "km", "my", "ru", "uk", "kk", "mn", "sr", "bg", "be", "ka", "hy", "lo", "am", "ne", "as",
        "ur", "fa", "ps", "sd", "ks", "dv", "ug", "ckb", "traditional", "latn", "cyrl", "arab", "deva",
    ]

    /// Category titles, for the keys in `categories.plist`. Keys without one are skipped.
    private nonisolated static let titles: [String: String] = [
        "communication": "Communication", "weather": "Weather", "maps": "Maps", "objectsandtools": "Objects & Tools",
        "devices": "Devices", "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
        "transportation": "Transportation", "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "Human", "home": "Home", "fitness": "Fitness",
        "nature": "Nature", "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
        "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math", "draw": "Draw",
    ]

    private nonisolated static func plist(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: directory.appending(path: "\(name).plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    private nonisolated static func read() -> SymbolCatalog {
        guard let order = plist("symbol_order") as? [String] else { return SymbolCatalog() }
        let all = Set(order)
        let names = order.filter { name in
            guard let dot = name.lastIndex(of: ".") else { return true }
            let suffix = String(name[name.index(after: dot)...])
            return !(localeSuffixes.contains(suffix) && all.contains(String(name[..<dot])))
        }
        var catalog = SymbolCatalog(names: names)
        catalog.keywords = plist("symbol_search") as? [String: [String]] ?? [:]
        let memberOf = plist("symbol_categories") as? [String: [String]] ?? [:]
        for (name, keys) in memberOf { for key in keys { catalog.membership[key, default: []].insert(name) } }
        let list = plist("categories") as? [[String: String]] ?? []
        catalog.categories = list.compactMap { entry in
            guard let key = entry["key"], let title = titles[key], catalog.membership[key] != nil else { return nil }
            return Category(id: key, title: title, icon: entry["icon"] ?? "square.grid.2x2")
        }
        return catalog
    }

    /// Symbols in a category (nil for all) whose name or keywords contain the query.
    func symbols(in category: String?, matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let members = category.flatMap { membership[$0] }
        return names.filter { name in
            if let members, !members.contains(name) { return false }
            guard !q.isEmpty else { return true }
            let words = q.split(separator: " ")
            return words.allSatisfy { word in
                name.contains(word) || (keywords[name]?.contains { $0.contains(word) } ?? false)
            }
        }
    }
}
