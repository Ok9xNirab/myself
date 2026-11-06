import SwiftUI
import UniformTypeIdentifiers

enum BookSort: String, CaseIterable, Identifiable {
    case recent, title, author, progress

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recently active"
        case .title: "Title"
        case .author: "Author"
        case .progress: "Progress"
        }
    }
}

/// Book Notes: the library (shelves, grid or list) and, for an open book, its workspace: the book panel and notes on
/// the left, the note editor on the right. Fills the detail column instead of using `PageScroll`.
struct BooksView: View {
    @Environment(AppStore.self) private var store

    @AppStorage("books.open") private var openBookID = ""
    @AppStorage("books.note") private var openNoteID = ""
    /// A book just added, so its panel focuses the title.
    @State private var freshBook: ID?

    var body: some View {
        Group {
            if let book = store.book(openBookID) {
                BookWorkspace(book: book, openNoteID: $openNoteID, focusTitle: freshBook == book.id) { openBookID = "" }
                    .id(book.id)
            } else {
                BookLibrary { book, fresh in
                    if fresh { freshBook = book }
                    openBookID = book
                }
            }
        }
        .overlay(alignment: .top) { Divider() }
        .onAppear { handle(store.bookNoteRequest) }
        .onChange(of: store.bookNoteRequest) { handle(store.bookNoteRequest) }
        .onDisappear {
            store.saveUnsavedNotes()
            store.saveUnsavedBooks()
        }
    }

    private func handle(_ request: ID?) {
        guard let request else { return }
        store.bookNoteRequest = nil
        guard let bookID = store.notes.first(where: { $0.id == request })?.bookID else { return }
        openBookID = bookID
        openNoteID = request
    }
}

// MARK: - Library

private struct BookLibrary: View {
    var onOpen: (ID, Bool) -> Void

    @Environment(AppStore.self) private var store
    /// "all", "none" or a category ID.
    @AppStorage("books.scope") private var scope = "all"
    /// "all" or a `BookStatus` raw value.
    @AppStorage("books.filter") private var filter = "all"
    @AppStorage("books.sort") private var sort = BookSort.recent
    @AppStorage("books.layout") private var layout = "grid"
    @State private var query = ""
    @State private var renaming: BookCategory?
    @State private var renameText = ""
    @State private var deleting: BookCategory?

    private static let shelfMax = 12

    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let books: [Book]
        let category: BookCategory?
        let seeAll: () -> Void
    }

    private var validScope: String {
        scope == "all" || scope == "none" || store.bookCategory(scope) != nil ? scope : "all"
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var showsShelves: Bool { validScope == "all" && trimmedQuery.isEmpty && filter == "all" && layout != "list" }

    var body: some View {
        // What each book's rows and sort order need of its notes.
        let notes = Dictionary(grouping: store.noteSummaries.filter { $0.bookID != nil }) { $0.bookID ?? "" }
        GeometryReader { geo in
            let side: CGFloat = geo.size.width <= 640 ? 20 : 32
            VStack(spacing: 0) {
                bar(width: geo.size.width)
                    .padding(.horizontal, side)
                    .padding(.vertical, 10)
                ScrollView {
                    Group {
                        if showsShelves {
                            shelves(notes, side: side, width: geo.size.width)
                        } else {
                            filtered(notes, width: geo.size.width)
                        }
                    }
                    .padding(.horizontal, side)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Palette.surface)
        .alert("Rename Category", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let renaming { store.renameBookCategory(renaming.id, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { store.deleteBookCategory(deleting.id) }
            }
        } message: {
            let n = store.books.count(where: { $0.categoryID == deleting?.id })
            Text("\(plural(n, "book")) will become uncategorized.")
        }
    }

    // MARK: Bar

    private func bar(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            if validScope != "all" || filter != "all" {
                Button {
                    scope = "all"
                    filter = "all"
                    query = ""
                } label: {
                    Label("All Books", systemImage: "chevron.left").font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            } else if width > 760 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Library").font(.system(size: 13, weight: .semibold))
                    Text(summary(store.books)).font(.system(size: 12.5)).foregroundStyle(Palette.ink3).monospacedDigit()
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            NoteSearchField(placeholder: "Search books", text: $query)
                .frame(width: width <= 900 ? 150 : 200)
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(BookSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Palette.ink2)
            .help("Sort")
            Picker("Layout", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag("grid").help("Covers")
                Image(systemName: "list.bullet").tag("list").help("List")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button(action: addBook) {
                Label("Add Book", systemImage: "plus")
                    .labelStyle(AddBookLabelStyle(compact: width <= 640))
            }
            .buttonStyle(.borderedProminent)
            .help("Add a book")
        }
    }

    private struct AddBookLabelStyle: LabelStyle {
        var compact: Bool

        func makeBody(configuration: Configuration) -> some View {
            if compact {
                configuration.icon
            } else {
                HStack(spacing: 5) {
                    configuration.icon
                    configuration.title
                }
            }
        }
    }

    // MARK: Shelves

    private func shelves(_ notes: [ID: [NoteSummary]], side: CGFloat, width: CGFloat) -> some View {
        let shelves = shelfList(notes)
        let height: CGFloat = width <= 640 ? 156 : width <= 900 ? 176 : 200
        return LazyVStack(alignment: .leading, spacing: 0) {
            if shelves.isEmpty {
                libraryEmpty("Your library is empty", action: "Add a book")
            }
            ForEach(Array(shelves.enumerated()), id: \.element.id) { i, shelf in
                VStack(alignment: .leading, spacing: 0) {
                    if i > 0 { Divider() }
                    HStack(spacing: 16) {
                        Button(action: shelf.seeAll) {
                            HStack(spacing: 2) {
                                Text(shelf.title).font(.system(size: 24, weight: .bold, design: .serif))
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { if let category = shelf.category { categoryMenu(category) } }
                        Spacer()
                        if shelf.books.count > Self.shelfMax {
                            Button("See All \(shelf.books.count)", action: shelf.seeAll)
                                .buttonStyle(.borderless)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.top, 26)
                    Text(shelf.subtitle).font(.system(size: 13.5)).foregroundStyle(Palette.ink3).padding(.top, 3)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .bottom, spacing: width <= 640 ? 22 : 30) {
                            ForEach(shelf.books.prefix(Self.shelfMax)) { book in
                                BookItem(book: book, notes: notes[book.id]?.count ?? 0, coverHeight: height) { onOpen(book.id, false) }
                            }
                        }
                        .padding(.horizontal, side)
                        .padding(.vertical, 22)
                    }
                    .scrollIndicators(.never)
                    .padding(.horizontal, -side)
                }
            }
        }
    }

    private func shelfList(_ notes: [ID: [NoteSummary]]) -> [Shelf] {
        let books = store.books
        let recent = books.sorted { activity($0, notes) > activity($1, notes) }
        var out = [
            Shelf(id: "reading", title: "Continue Reading", subtitle: "Pick up where you left off.", books: recent.filter { $0.status == .reading }, category: nil) { filter = BookStatus.reading.rawValue },
            Shelf(id: "want", title: "Want to Read", subtitle: "Up next on your list.", books: recent.filter { $0.status == .want }, category: nil) { filter = BookStatus.want.rawValue },
        ]
        for category in store.bookCategories {
            let shelf = sorted(books.filter { $0.categoryID == category.id }, notes)
            out.append(Shelf(id: category.id, title: category.name, subtitle: summary(shelf), books: shelf, category: category) { pick(category.id) })
        }
        let loose = sorted(books.filter { book in book.categoryID.flatMap(store.bookCategory) == nil }, notes)
        out.append(Shelf(id: "none", title: "Uncategorized", subtitle: summary(loose), books: loose, category: nil) { pick("none") })
        return out.filter { !$0.books.isEmpty }
    }

    @ViewBuilder
    private func categoryMenu(_ category: BookCategory) -> some View {
        Button("Rename", systemImage: "pencil") {
            renameText = category.name
            renaming = category
        }
        Button("Delete Category", systemImage: "trash", role: .destructive) {
            if store.books.contains(where: { $0.categoryID == category.id }) {
                deleting = category
            } else {
                store.deleteBookCategory(category.id)
            }
        }
    }

    // MARK: Filtered

    private func filtered(_ notes: [ID: [NoteSummary]], width: CGFloat) -> some View {
        let q = trimmedQuery
        let category = store.bookCategory(validScope)
        let scoped = store.books.filter { book in
            switch validScope {
            case "all": true
            case "none": book.categoryID.flatMap(store.bookCategory) == nil
            default: book.categoryID == validScope
            }
        }
        let list = sorted(scoped.filter { book in
            (filter == "all" || book.status.rawValue == filter) && (q.isEmpty || "\(book.title) \(book.author)".lowercased().contains(q))
        }, notes)
        let title = if !q.isEmpty {
            "Results"
        } else if filter != "all", validScope == "all" {
            BookStatus(rawValue: filter)?.title ?? "All Books"
        } else {
            validScope == "all" ? "All Books" : validScope == "none" ? "Uncategorized" : category?.name ?? "All Books"
        }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 30, weight: .bold, design: .serif))
                    .contextMenu { if let category { categoryMenu(category) } }
                Text(q.isEmpty ? plural(list.count, "book") : "\(plural(list.count, "book")) matching \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.ink3)
                Picker("Status", selection: Binding(get: { filter }, set: { filter = $0 })) {
                    Text("All \(scoped.count)").tag("all")
                    ForEach(BookStatus.allCases) { status in
                        Text("\(status.title) \(scoped.count(where: { $0.status == status }))").tag(status.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 13)
            }
            .padding(.top, 24)
            .padding(.bottom, 18)

            if list.isEmpty {
                if q.isEmpty {
                    libraryEmpty("Nothing here yet", action: "Add a book")
                } else {
                    libraryEmpty("No books match \u{201C}\(query)\u{201D}", action: nil)
                }
            } else if layout == "list" {
                BookList(books: list, notes: notes, width: width) { onOpen($0, false) }
            } else {
                let compact = width <= 640
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 104 : 136), spacing: compact ? 20 : 30, alignment: .bottom)], spacing: compact ? 30 : 40) {
                    ForEach(list) { book in
                        BookItem(book: book, notes: notes[book.id]?.count ?? 0, coverHeight: nil) { onOpen(book.id, false) }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func libraryEmpty(_ title: String, action: String?) -> some View {
        VStack(spacing: 8) {
            Text(title)
            if let action { Button(action, action: addBook).buttonStyle(.borderless) }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink3)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Helpers

    private func pick(_ newScope: String) {
        scope = newScope
        filter = "all"
    }

    private func addBook() {
        let status = BookStatus(rawValue: filter) ?? .reading
        let book = store.addBook(status: status, categoryID: store.bookCategory(validScope)?.id)
        onOpen(book.id, true)
    }

    /// A book's latest reading note, or when it was added.
    private func activity(_ book: Book, _ notes: [ID: [NoteSummary]]) -> Date {
        notes[book.id]?.map(\.editedAt).max() ?? book.createdAt
    }

    private func sorted(_ books: [Book], _ notes: [ID: [NoteSummary]]) -> [Book] {
        switch sort {
        case .recent: books.sorted { activity($0, notes) > activity($1, notes) }
        case .title: books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            books.sorted {
                let order = $0.author.localizedStandardCompare($1.author)
                return order == .orderedSame ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : order == .orderedAscending
            }
        case .progress: books.sorted { $0.percent > $1.percent }
        }
    }

    /// "12 books · 2 reading · 5 finished"
    private func summary(_ books: [Book]) -> String {
        let reading = books.count(where: { $0.status == .reading })
        let done = books.count(where: { $0.status == .done })
        return ([plural(books.count, "book")] + (reading > 0 ? ["\(reading) reading"] : []) + (done > 0 ? ["\(done) finished"] : [])).joined(separator: " · ")
    }
}

private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

/// A cover with its reading progress and note count underneath. With no `coverHeight` it fills its column's width.
private struct BookItem: View {
    var book: Book
    var notes: Int
    var coverHeight: CGFloat?
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let coverHeight {
                        BookCover(book: book).frame(height: coverHeight)
                    } else {
                        BookCover(book: book).frame(maxWidth: .infinity)
                    }
                }
                .offset(y: hovering ? -5 : 0)
                .animation(.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.22), value: hovering)
                HStack(spacing: 7) {
                    if book.status == .reading {
                        ProgressBar(value: Double(book.percent), color: Palette.ink2, height: 3).frame(minWidth: 16, maxWidth: 40)
                        Text("\(book.percent)%").fixedSize()
                    } else {
                        Text(book.status.title).lineLimit(1)
                    }
                    if notes > 0 {
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            Image(systemName: "note.text").font(.system(size: 9))
                            Text("\(notes)")
                        }
                        .fixedSize()
                        .help(plural(notes, "note"))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ink3)
                .monospacedDigit()
                .frame(height: 14)
                // A shelf's cover sets the width; the line under it shouldn't widen it.
                .frame(maxWidth: coverHeight == nil ? .infinity : coverHeight! * 2 / 3, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(book.displayTitle + (book.author.isEmpty ? "" : " \u{2014} \(book.author)"))
    }
}

/// The library as rows. Columns drop away as the page narrows, as in the design.
private struct BookList: View {
    var books: [Book]
    var notes: [ID: [NoteSummary]]
    var width: CGFloat
    var onOpen: (ID) -> Void
    @Environment(AppStore.self) private var store

    private var showsAuthorAndCategory: Bool { width > 560 }
    private var showsProgressAndNotes: Bool { width > 1080 }

    var body: some View {
        LazyVStack(spacing: 0) {
            row(cover: AnyView(Color.clear), title: AnyView(Text("Title")), author: AnyView(Text("Author")), status: AnyView(Text("Status")),
                progress: AnyView(Text("Progress")), category: AnyView(Text("Category")), notes: AnyView(Text("Notes")))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink3)
                .frame(height: 26)
            Divider()
            ForEach(Array(books.enumerated()), id: \.element.id) { i, book in
                BookRowButton(striped: i % 2 == 0) { onOpen(book.id) } label: { rowContent(book) }
            }
        }
    }

    private func rowContent(_ book: Book) -> some View {
        let category = book.categoryID.flatMap(store.bookCategory)
        return row(
            cover: AnyView(BookCover(book: book, small: true)),
            title: AnyView(Text(book.displayTitle).fontWeight(.semibold).lineLimit(1)),
            author: AnyView(Text(book.author.isEmpty ? "\u{2014}" : book.author).foregroundStyle(Palette.ink2).lineLimit(1)),
            status: AnyView(BookStatusBadge(status: book.status)),
            progress: AnyView(HStack(spacing: 8) {
                ProgressBar(value: Double(book.percent), color: book.color, height: 4)
                Text("\(book.percent)%").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink2).monospacedDigit()
            }),
            category: AnyView(HStack(spacing: 6) {
                if let category {
                    ColorDot(color: category.color, size: 6)
                    Text(category.name).foregroundStyle(Palette.ink2).lineLimit(1)
                } else {
                    Text("\u{2014}").foregroundStyle(Palette.ink3)
                }
            }.font(.system(size: 12))),
            notes: AnyView(Text(notes[book.id]?.count.formatted() ?? "\u{2014}").monospacedDigit())
        )
        .font(.system(size: 13))
        .frame(height: 52)
    }

    private func row(cover: AnyView, title: AnyView, author: AnyView, status: AnyView, progress: AnyView, category: AnyView, notes: AnyView) -> some View {
        HStack(spacing: 14) {
            cover.frame(width: 28)
            title.frame(maxWidth: .infinity, alignment: .leading)
            if showsAuthorAndCategory { author.frame(maxWidth: .infinity, alignment: .leading) }
            status.frame(width: 100, alignment: .leading)
            if showsProgressAndNotes { progress.frame(width: 120) }
            if showsAuthorAndCategory { category.frame(maxWidth: .infinity, alignment: .leading) }
            if showsProgressAndNotes { notes.frame(width: 52, alignment: .trailing) }
        }
        .padding(.horizontal, 10)
    }
}

private struct BookRowButton<Label: View>: View {
    var striped: Bool
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            label
                .background { HoverFill(hover: hover, color: Color.primary.opacity(0.06)) }
                .background(striped ? Color.primary.opacity(0.025) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}

private struct BookStatusBadge: View {
    var status: BookStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(status == .want ? Palette.ink2 : status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background((status == .want ? Color.primary.opacity(0.07) : status.color.opacity(0.15)), in: Capsule())
    }
}

// MARK: - Cover

/// A book's uploaded cover, or a generated one: its colour with a printed spine, the title and the author.
struct BookCover: View {
    var book: Book
    /// A list row's thumbnail, without text.
    var small = false

    @Environment(AppStore.self) private var store
    @State private var image: CGImage?

    private var shape: UnevenRoundedRectangle {
        let (left, right): (CGFloat, CGFloat) = small ? (1, 2) : (2, 4)
        return UnevenRoundedRectangle(topLeadingRadius: left, bottomLeadingRadius: left, bottomTrailingRadius: right, topTrailingRadius: right, style: .continuous)
    }

    var body: some View {
        Group {
            if let image, book.cover != nil {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                generated.aspectRatio(2.0 / 3.0, contentMode: .fit)
            }
        }
        .overlay { spine }
        .clipShape(shape)
        .background {
            // On a background shape, so a change to the cover doesn't render it all offscreen again.
            shape.fill(book.color)
                .shadow(color: .black.opacity(small ? 0.25 : 0.32), radius: small ? 2 : 10, y: small ? 1 : 8)
        }
        .task(id: book.cover) { await load() }
    }

    private var generated: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                book.color
                LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.4), .init(color: .black.opacity(0.2), location: 1)],
                               startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))
                if !small {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(book.title.isEmpty ? "Untitled" : book.title)
                            .font(.system(size: width * 0.12, weight: .semibold, design: .serif))
                            .lineSpacing(-width * 0.01)
                            .lineLimit(5)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        if !book.author.isEmpty {
                            Rectangle().fill(.white.opacity(0.4)).frame(height: 0.5)
                            Text(book.author.uppercased())
                                .font(.system(size: max(5, width * 0.064), weight: .semibold))
                                .tracking(max(5, width * 0.064) * 0.12)
                                .lineLimit(1)
                                .opacity(0.85)
                                .padding(.top, 6)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, width * 0.15)
                    .padding(.trailing, width * 0.11)
                    .padding(.top, width * 0.14)
                    .padding(.bottom, width * 0.11)
                }
            }
        }
    }

    private var spine: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.28), location: 0), .init(color: .white.opacity(0.22), location: 0.016),
            .init(color: .black.opacity(0.1), location: 0.036), .init(color: .white.opacity(0.06), location: 0.06),
            .init(color: .clear, location: 0.09),
        ], startPoint: .leading, endPoint: .trailing)
        .allowsHitTesting(false)
    }

    private func load() async {
        guard let name = book.cover else {
            image = nil
            return
        }
        while !Task.isCancelled {
            switch store.sync.imageState(name) {
            case .ready(let url):
                image = await Task.detached(priority: .userInitiated) { NoteImages.preview(at: url) }.value
                return
            case .missing:
                image = nil
                return
            case .downloading:
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - Workspace

/// One book: its panel and reading notes on the left, the open note on the right.
private struct BookWorkspace: View {
    var book: Book
    @Binding var openNoteID: String
    var focusTitle: Bool
    var onBack: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @AppStorage("books.browser") private var showsPanel = true
    @State private var freshNote: ID?

    /// The open note, or the book's first. Reads the summaries, so typing in the note doesn't redraw the panel.
    private var openNote: ID? {
        let notes = store.noteSummaries.filter { $0.bookID == book.id }
        return (notes.first { $0.id == openNoteID } ?? notes.min { $0.createdAt < $1.createdAt })?.id
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if showsPanel {
                    BookPanel(book: book, open: openNote, focusTitle: focusTitle, onBack: onBack, onOpenNote: { openNoteID = $0 }, onNewNote: newNote, onDeleteNote: deleteNote)
                        .frame(width: geo.size.width <= 700 ? 240 : geo.size.width <= 940 ? 256 : 288)
                        .background(Palette.surface.opacity(0.5))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                Group {
                    if let open = openNote {
                        OpenNoteEditor(id: open, isFresh: freshNote == open, showsBrowser: $showsPanel,
                                       onDuplicate: { duplicate(open) }, onDelete: { deleteNote(open) })
                            .id(open)
                    } else {
                        VStack(spacing: 0) {
                            if !showsPanel {
                                HStack {
                                    Button("Show Book", systemImage: "sidebar.left") { showsPanel = true }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.borderless)
                                    Spacer()
                                }
                                .padding(10)
                            }
                            EmptyStateView(systemImage: "book.pages", title: "Nothing written yet",
                                           subtitle: "Start a note while you read. Type [[ to link a word to any note.")
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface)
            }
            .background(Palette.background)
            .animation(.smooth(duration: 0.25), value: showsPanel)
        }
    }

    private func newNote() {
        let note = store.addBookNote(to: book.id)
        freshNote = note.id
        openNoteID = note.id
    }

    private func duplicate(_ id: ID) {
        if let copy = store.duplicateNote(id) { openNoteID = copy.id }
    }

    /// Deletes a note and opens the one that took its place.
    private func deleteNote(_ id: ID) {
        let order = store.noteSummaries.filter { $0.bookID == book.id }.sorted { $0.createdAt < $1.createdAt }.map(\.id)
        let at = order.firstIndex(of: id) ?? 0
        let rest = order.filter { $0 != id }
        store.deleteNotes([id], undoManager: undoManager)
        openNoteID = rest.isEmpty ? "" : rest[min(at, rest.count - 1)]
    }
}

/// The left side of a book's workspace: back, cover, title, author, category, progress, status and the notes list.
private struct BookPanel: View {
    var book: Book
    var open: ID?
    var focusTitle: Bool
    var onBack: () -> Void
    var onOpenNote: (ID) -> Void
    var onNewNote: () -> Void
    var onDeleteNote: (ID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage("books.scope") private var scope = "all"
    @State private var showsOptions = false
    @State private var showsCategories = false
    @State private var choosingCover = false
    @State private var droppingCover = false
    @State private var hoveringCover = false
    @State private var confirmsDelete = false
    @State private var query = ""
    @State private var index = NoteSearchIndex()
    @FocusState private var titleFocused: Bool

    private var notes: [NoteSummary] {
        store.noteSummaries.filter { $0.bookID == book.id }.sorted { $0.createdAt < $1.createdAt }
    }

    private var category: BookCategory? { book.categoryID.flatMap(store.bookCategory) }

    var body: some View {
        let notes = notes
        VStack(alignment: .leading, spacing: 0) {
            top
            header
            progress
            Picker("Status", selection: Binding(get: { book.status }, set: setStatus)) {
                ForEach(BookStatus.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            notesList(notes)
        }
        .onAppear { if focusTitle { titleFocused = true } }
        .fileImporter(isPresented: $choosingCover, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if let url = try? result.get().first { setCover(from: url) }
        }
        .confirmationDialog("Delete \u{201C}\(book.displayTitle)\u{201D}\(notes.isEmpty ? "" : " and its \(plural(notes.count, "note"))")?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                store.deleteBook(book.id, undoManager: undoManager)
                onBack()
            }
        } message: {
            Text("You can undo this with ⌘Z.")
        }
    }

    // MARK: Top

    private var top: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                    Text(category != nil && scope == category?.id ? category?.name ?? "Library" : "Library").lineLimit(1)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Book Options", systemImage: "ellipsis") { showsOptions = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.ink2)
                .help("Book options")
                .popover(isPresented: $showsOptions, arrowEdge: .bottom) { options }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 2) {
            optionRow(book.cover == nil ? "Upload Cover\u{2026}" : "Replace Cover\u{2026}", "photo") {
                showsOptions = false
                choosingCover = true
            }
            if book.cover != nil {
                optionRow("Remove Cover", "xmark") {
                    store.removeBookCover(book.id)
                    showsOptions = false
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Book.palette, id: \.self) { hex in
                        let selected = hex == book.hex
                        Button { store.editBook(book.id) { $0.hex = hex } } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .padding(2)
                                .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) } }
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Cover colour")
                        .accessibilityLabel("Cover colour")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            Divider().padding(.vertical, 3)
            optionRow("Delete Book", "trash", role: .destructive) {
                showsOptions = false
                confirmsDelete = true
            }
        }
        .padding(6)
    }

    private func optionRow(_ title: String, _ systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Palette.red : .primary)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            coverButton.frame(width: 92)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Book title", text: binding(\.title), axis: .vertical)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2...3)
                    .focused($titleFocused)
                TextField("Author", text: binding(\.author))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
                categoryButton.padding(.top, 4)
            }
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var coverButton: some View {
        Button { choosingCover = true } label: {
            BookCover(book: book)
                .overlay(alignment: .bottom) {
                    if hoveringCover || droppingCover {
                        Label(book.cover == nil ? "Add cover" : "Replace", systemImage: "photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
                }
                .overlay {
                    if droppingCover {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringCover = $0 }
        .help("Click or drop an image to set the cover")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            setCover(from: url)
            return true
        } isTargeted: { droppingCover = $0 }
    }

    private var categoryButton: some View {
        Button { showsCategories = true } label: {
            HStack(spacing: 6) {
                if let category {
                    ColorDot(color: category.color, size: 7)
                    Text(category.name).lineLimit(1)
                } else {
                    Image(systemName: "tag").font(.system(size: 10))
                    Text("Add category")
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12))
            .foregroundStyle(category == nil ? Palette.ink3 : .primary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsCategories, arrowEdge: .bottom) {
            BookCategoryPicker(selection: book.categoryID) { id in
                store.editBook(book.id) { $0.categoryID = id }
                showsCategories = false
            }
        }
    }

    // MARK: Progress

    private var progress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("Page")
                pageField(Binding(get: { book.currentPage }, set: setCurrentPage))
                Text("of")
                pageField(Binding(get: { book.totalPages }, set: { value in store.editBook(book.id) { $0.totalPages = value } }))
                Spacer(minLength: 0)
                Text("\(book.percent)%").fontWeight(.semibold).foregroundStyle(Palette.ink2).monospacedDigit()
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink3)
            ProgressBar(value: Double(book.percent), color: book.color, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func pageField(_ value: Binding<Int>) -> some View {
        TextField("", text: Binding(get: { "\(value.wrappedValue)" }, set: { text in
            value.wrappedValue = min(99999, Int(text.filter(\.isNumber)) ?? 0)
        }))
        .textFieldStyle(.plain)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: 42)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }

    /// Reaching the last page finishes the book, and any other page means it's being read.
    private func setCurrentPage(_ value: Int) {
        store.editBook(book.id) { book in
            book.currentPage = book.totalPages > 0 ? min(value, book.totalPages) : value
            if book.totalPages > 0, book.currentPage >= book.totalPages {
                book.status = .done
            } else if book.currentPage > 0 {
                book.status = .reading
            }
        }
    }

    private func setStatus(_ status: BookStatus) {
        store.editBook(book.id) { book in
            book.status = status
            if status == .done { book.currentPage = book.totalPages }
        }
    }

    // MARK: Notes

    private func notesList(_ notes: [NoteSummary]) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        // Searching needs the notes' text; only then does the list follow every edit.
        let shown = q.isEmpty ? notes : notes.filter { summary in
            guard let note = store.notes.first(where: { $0.id == summary.id }) else { return false }
            return "\(index.text(for: note)) \((note.location ?? "").lowercased())".contains(q)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.top, 8)
            HStack(spacing: 6) {
                Text("Reading notes").font(.system(size: 11, weight: .semibold))
                Text("\(notes.count)").font(.system(size: 11)).monospacedDigit()
                Spacer()
                Button("New Reading Note", systemImage: "square.and.pencil", action: onNewNote)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink2)
                    .help("New reading note")
            }
            .foregroundStyle(Palette.ink3)
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
            if notes.count > 5 {
                NoteSearchField(placeholder: "Search notes in this book", text: $query)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            if notes.isEmpty {
                listMessage("No notes for this book yet", action: ("Start a reading note", onNewNote))
            } else if shown.isEmpty {
                listMessage("No notes match \u{201C}\(query)\u{201D}", action: nil)
            } else {
                List(selection: Binding(get: { open }, set: { if let id = $0 { onOpenNote(id) } })) {
                    ForEach(shown) { note in
                        BookNoteRow(note: note).tag(note.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                #if os(macOS)
                .contextMenu(forSelectionType: ID.self) { ids in
                    if let id = ids.first { rowMenu(id) }
                } primaryAction: { ids in
                    ids.forEach { openWindow(id: NoteWindow.id, value: $0) }
                }
                #else
                .contextMenu(forSelectionType: ID.self) { ids in
                    if let id = ids.first { rowMenu(id) }
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ id: ID) -> some View {
        #if os(macOS)
        Button("Open in New Window", systemImage: "macwindow") { openWindow(id: NoteWindow.id, value: id) }
        #endif
        Button("Duplicate", systemImage: "plus.square.on.square") {
            if let copy = store.duplicateNote(id) { onOpenNote(copy.id) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { onDeleteNote(id) }
    }

    private func listMessage(_ text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Text(text)
            if let action { Button(action.0, action: action.1).buttonStyle(.borderless) }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 30)
    }

    // MARK: Helpers

    private func binding(_ field: WritableKeyPath<Book, String>) -> Binding<String> {
        Binding(get: { book[keyPath: field] }, set: { value in
            store.editBook(book.id) { $0[keyPath: field] = value.replacingOccurrences(of: "\n", with: "") }
        })
    }

    private func setCover(from url: URL) {
        if let file = NoteImages.read(url) { store.setBookCover(book.id, data: file.data) }
    }
}

private struct BookNoteRow: View {
    var note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !note.linkIDs.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "link").font(.system(size: 9, weight: .medium))
                        Text("\(note.linkIDs.count)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .help(plural(note.linkIDs.count, "linked note"))
                }
            }
            HStack(spacing: 6) {
                if let location = note.location {
                    Text(location).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
                }
                Text(note.snippet).foregroundStyle(.tertiary).lineLimit(1)
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 5)
    }
}

/// The shelves a book can go on, and a field to make a new one.
private struct BookCategoryPicker: View {
    var selection: ID?
    var onPick: (ID?) -> Void

    @Environment(AppStore.self) private var store
    @State private var newName: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Category").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.horizontal, 6).padding(.vertical, 3)
            ForEach(store.bookCategories) { category in
                row(category.name, selected: selection == category.id) { ColorDot(color: category.color, size: 8) } action: { onPick(category.id) }
            }
            row("No category", selected: selection == nil) {
                Image(systemName: "xmark").font(.system(size: 10))
            } action: { onPick(nil) }
            Divider().padding(.vertical, 3)
            if let newName {
                TextField("Category name", text: Binding(get: { newName }, set: { self.newName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .onSubmit {
                        if let category = store.addBookCategory(name: newName) { onPick(category.id) }
                    }
            } else {
                row("New category\u{2026}", selected: false) {
                    Image(systemName: "plus").font(.system(size: 11))
                } action: { newName = "" }
            }
        }
        .padding(6)
        .frame(width: 210)
    }

    private func row<Icon: View>(_ title: String, selected: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon().frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 6)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
