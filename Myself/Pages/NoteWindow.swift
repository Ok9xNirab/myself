#if os(macOS)
import AppKit
import SwiftUI

/// A note in its own window, opened by double-clicking it in the note list. Edits go through the same store as the Notes page.
struct NoteWindow: View {
    static let id = "note"

    var noteID: ID

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let note = store.notes.first(where: { $0.id == noteID }) {
                NoteEditor(note: note, isFresh: false,
                           onDuplicate: duplicate, onDelete: delete)
                    .navigationTitle(note.displayTitle)
                    .navigationSubtitle(store.noteCategory(note.categoryID)?.name ?? "")
            } else {
                EmptyStateView(systemImage: "note.text", title: "Note not found", subtitle: "It may have been deleted on another Mac.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Note")
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Palette.surface)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Show in Notes", systemImage: "arrow.up.forward.app", action: showInNotes)
                    .help("Show this note on the Notes page")
            }
        }
        .onDisappear { store.saveUnsavedNotes() }
    }

    private func duplicate() {
        guard let copy = store.duplicateNote(noteID) else { return }
        openWindow(id: Self.id, value: copy.id)
    }

    private func delete() {
        store.deleteNotes([noteID], undoManager: undoManager)
        dismiss()
    }

    /// Opens the note on the Notes page and brings the main window forward, opening one if it was closed.
    private func showInNotes() {
        store.openNote(noteID)
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
#endif
