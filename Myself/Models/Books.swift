import SwiftUI

enum BookStatus: String, Codable, CaseIterable, Identifiable {
    case reading, want, done

    var id: Self { self }

    var title: String {
        switch self {
        case .reading: "Reading"
        case .want: "Want to read"
        case .done: "Finished"
        }
    }

    /// The book panel's segmented control has little room.
    var shortTitle: String { self == .want ? "Want" : title }

    var color: Color {
        switch self {
        case .reading: .accentColor
        case .want: Palette.ink3
        case .done: Palette.green
        }
    }
}

/// A shelf in the Book Notes library. These are separate from note categories.
struct BookCategory: Identifiable, Hashable, Codable, SyncRecord {
    static let folder = "bookcats"

    let id: ID
    var name: String
    var hex: UInt32
    var sortOrder = 0
    var updatedAt = Date.now
    var color: Color { Color(hex: hex) }
}

/// A book in the library. Its reading notes are `Note`s with `bookID` set to its ID.
struct Book: Identifiable, Equatable, Codable, SyncRecord {
    static let folder = "books"

    var id = newID()
    var title = ""
    var author = ""
    /// The generated cover's colour.
    var hex: UInt32
    var status = BookStatus.reading
    var categoryID: ID?
    var totalPages = 300
    var currentPage = 0
    /// The uploaded cover's file name, stored like a note image (`NoteImageModel`).
    var cover: String?
    var createdAt = Date.now
    var updatedAt = Date.now

    var color: Color { Color(hex: hex) }
    var displayTitle: String { title.isEmpty ? "Untitled book" : title }
    var percent: Int { totalPages > 0 ? Int((min(1, Double(currentPage) / Double(totalPages)) * 100).rounded()) : 0 }

    /// Generated cover colours, from the design's `BK_COLORS`.
    static let palette: [UInt32] = [0x2F5D8E, 0x8E3B2F, 0x3D7A4F, 0x7A5A2F, 0x5B3F8A, 0x2F7A7A, 0x8A2F5D, 0x4A4A4A]
}
