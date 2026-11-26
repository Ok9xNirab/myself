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

/// The design's Book Notes brown, for the "Now reading" tag, progress bars and page numbers.
private var bookTint: Color { Page.books.tint }

/// Book Notes: the library (the v2 design's header, "Now reading" cards and the shelves by category) and, for an
/// open book, its workspace: the book panel and notes on the left, the note editor on the right.
struct BooksView: View {
    @Environment(AppStore.self) private var store

    @AppStorage("books.open") private var openBookID = ""
    @AppStorage("books.note") private var openNoteID = ""
    /// A book just added, so its panel focuses the title.
    @State private var freshBook: ID?

    var body: some View {
        let book = store.book(openBookID)
        Group {
            if let book {
                BookWorkspace(book: book, openNoteID: $openNoteID, focusTitle: freshBook == book.id) { openBookID = "" }
                    .id(book.id)
                    .overlay(alignment: .top) { Divider() }
            } else {
                BookLibrary { book, fresh in
                    if fresh { freshBook = book }
                    openBookID = book
                }
            }
        }
        .onAppear {
            handle(store.bookNoteRequest)
            updateCrumb(book)
        }
        .onChange(of: store.bookNoteRequest) { handle(store.bookNoteRequest) }
        .onChange(of: store.homeRequest) {
            guard store.homeRequest == .books else { return }
            store.homeRequest = nil
            openBookID = ""
        }
        .onChange(of: book?.displayTitle) { updateCrumb(book) }
        .onDisappear {
            store.saveUnsavedNotes()
            store.saveUnsavedBooks()
            if store.crumb?.page == .books { store.crumb = nil }
        }
    }

    private func handle(_ request: ID?) {
        guard let request else { return }
        store.bookNoteRequest = nil
        guard let bookID = store.notes.first(where: { $0.id == request })?.bookID else { return }
        openBookID = bookID
        openNoteID = request
    }

    /// "Book Notes / Library", or the open book's title.
    private func updateCrumb(_ book: Book?) {
        store.crumb = (page: .books, detail: book?.displayTitle ?? "Library")
    }
}

// MARK: - Library

private struct BookLibrary: View {
    var onOpen: (ID, Bool) -> Void

    @Environment(AppStore.self) private var store
    /// "all", "none" or a category ID: "See all" shows one category.
    @AppStorage("books.scope") private var scope = "all"
    /// "all" or a `BookStatus` raw value.
    @AppStorage("books.filter") private var filter = "all"
    @AppStorage("books.sort") private var sort = BookSort.recent
    @State private var query = ""
    @State private var renaming: BookCategory?
    @State private var renameText = ""
    @State private var deleting: BookCategory?
    @State private var showsManage = false

    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let color: Color
        let books: [Book]
        let category: BookCategory?
    }

    private var validScope: String {
        scope == "all" || scope == "none" || store.bookCategory(scope) != nil ? scope : "all"
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        // What each book's sort order needs of its notes.
        let notes = Dictionary(grouping: store.noteSummaries.filter { $0.bookID != nil }) { $0.bookID ?? "" }
        let scope = validScope
        PageScroll {
            SpaceHeader(page: .books, detail: summary(store.books))
            if store.books.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(systemImage: "books.vertical", title: "Your library is empty",
                                   subtitle: "Add a book to keep its reading notes, quotes and progress together.")
                    Button("Add Book", systemImage: "plus", action: addBook)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                if scope == "all" {
                    let reading = sorted(store.books.filter { $0.status == .reading }, notes, by: .recent)
                    if !reading.isEmpty { NowReading(books: Array(reading.prefix(4))) { onOpen($0, false) } }
                }
                libraryBar(scope)
                library(notes, scope: scope)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showsManage) { BookCategoriesSheet() }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(BookSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Manage Categories\u{2026}", systemImage: "slider.horizontal.3") { showsManage = true }
            } label: {
                Label("Sort and Categories", systemImage: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("Sort books, manage categories")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add book", systemImage: "plus", action: addBook)
                .labelStyle(.titleAndIcon)
                .help("Add a book")
        }
    }

    // MARK: Bar

    /// "Library" (or the category "See all" opened, with a way back), the status filter and the search field.
    private func libraryBar(_ scope: String) -> some View {
        let category = store.bookCategory(scope)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title(scope, category)
                Spacer(minLength: 8)
                statusTabs
                search
            }
            VStack(alignment: .leading, spacing: 12) {
                title(scope, category)
                HStack(spacing: 12) {
                    statusTabs
                    search
                }
            }
        }
        .padding(.top, 8)
    }

    private func title(_ scope: String, _ category: BookCategory?) -> some View {
        HStack(spacing: 8) {
            if scope != "all" {
                Button { self.scope = "all" } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to the library")
                if let category { ColorDot(color: category.color, size: 9) }
            }
            Text(scope == "all" ? "Library" : scope == "none" ? "Uncategorized" : category?.name ?? "Library")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .lineLimit(1)
                .contextMenu { if let category { categoryMenu(category) } }
        }
        .fixedSize()
    }

    private var statusTabs: some View {
        SegmentedTabs(options: ["all"] + BookStatus.allCases.map(\.rawValue),
                      title: { BookStatus(rawValue: $0)?.title ?? "All" },
                      selection: Binding(get: { BookStatus(rawValue: filter) == nil ? "all" : filter }, set: { filter = $0 }))
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onEscape { query = "" }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 28)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    // MARK: Shelves

    @ViewBuilder
    private func library(_ notes: [ID: [NoteSummary]], scope: String) -> some View {
        let shelves = shelfList(notes, scope: scope)
        if shelves.isEmpty {
            Text(trimmedQuery.isEmpty ? "No books here yet." : "No books match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 2)
                .padding(.vertical, 24)
        } else if scope != "all", let shelf = shelves.first {
            BookGrid(books: shelf.books) { onOpen($0, false) }
                .padding(.top, 6)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shelves) { shelf in
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        shelfHeader(shelf)
                        BookGrid(books: shelf.books) { onOpen($0, false) }
                    }
                    .padding(.bottom, 22)
                }
            }
        }
    }

    private func shelfHeader(_ shelf: Shelf) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            ColorDot(color: shelf.color, size: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(shelf.title).font(.system(size: 19, weight: .bold, design: .serif)).lineLimit(1)
            Text(plural(shelf.books.count, "book")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Button { scope = shelf.id } label: {
                HStack(spacing: 2) {
                    Text("See all")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 14)
        .contextMenu { if let category = shelf.category { categoryMenu(category) } }
    }

    /// One shelf per category, then Uncategorized, each holding the books that pass the filter and search. In one
    /// category's view, just that shelf.
    private func shelfList(_ notes: [ID: [NoteSummary]], scope: String) -> [Shelf] {
        let q = trimmedQuery
        let books = store.books.filter { book in
            (filter == "all" || book.status.rawValue == filter) && (q.isEmpty || "\(book.title) \(book.author)".lowercased().contains(q))
        }
        var out = store.bookCategories.map { category in
            Shelf(id: category.id, title: category.name, color: category.color,
                  books: sorted(books.filter { $0.categoryID == category.id }, notes, by: sort), category: category)
        }
        let loose = books.filter { book in book.categoryID.flatMap(store.bookCategory) == nil }
        out.append(Shelf(id: "none", title: "Uncategorized", color: Palette.ink3, books: sorted(loose, notes, by: sort), category: nil))
        if scope != "all" { out = out.filter { $0.id == scope } }
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
        Divider()
        Button("Manage Categories\u{2026}", systemImage: "slider.horizontal.3") { showsManage = true }
    }

    // MARK: Helpers

    private func addBook() {
        let status = BookStatus(rawValue: filter) ?? .reading
        let book = store.addBook(status: status, categoryID: store.bookCategory(validScope)?.id)
        onOpen(book.id, true)
    }

    /// A book's latest reading note, or when it was added.
    private func activity(_ book: Book, _ notes: [ID: [NoteSummary]]) -> Date {
        notes[book.id]?.map(\.editedAt).max() ?? book.createdAt
    }

    private func sorted(_ books: [Book], _ notes: [ID: [NoteSummary]], by sort: BookSort) -> [Book] {
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

// MARK: - Now reading

/// The books being read, as cards: a tilted cover, the title, progress, what's left and Resume. Two to a row.
private struct NowReading: View {
    var books: [Book]
    var onOpen: (ID) -> Void
    @Environment(\.pageWidth) private var width

    var body: some View {
        let columns = width >= 760 ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns), spacing: 12) {
            ForEach(books) { book in
                NowReadingCard(book: book) { onOpen(book.id) }
            }
        }
    }
}

private struct NowReadingCard: View {
    var book: Book
    var onOpen: () -> Void
    @State private var hover = HoverState()

    /// "303 pages left · ~10 sessions", at the design's 30 pages a session.
    private var left: String {
        guard book.totalPages > 0 else { return "No page count" }
        let pages = max(0, book.totalPages - book.currentPage)
        let sessions = max(1, Int((Double(pages) / 30).rounded()))
        return pages == 0 ? "Last page reached" : "\(plural(pages, "page")) left · ~\(plural(sessions, "session"))"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 16) {
                BookCover(book: book)
                    .frame(width: 96, height: 144)
                    .rotation3DEffect(.degrees(-14), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                    .padding(.trailing, 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text("NOW READING")
                        .font(.system(size: 10.5, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(bookTint)
                    Text(book.displayTitle)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .lineLimit(2)
                        .padding(.top, 5)
                    if !book.author.isEmpty {
                        Text(book.author).font(.system(size: 12.5)).foregroundStyle(Palette.ink2).lineLimit(1).padding(.top, 3)
                    }
                    Spacer(minLength: 12)
                    ProgressBar(value: Double(book.percent), color: bookTint, height: 5)
                    (Text("\(book.percent)%").fontWeight(.bold).foregroundStyle(.primary)
                        + Text(book.totalPages > 0 ? " · p. \(book.currentPage) of \(book.totalPages)" : ""))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink2)
                        .monospacedDigit()
                        .padding(.top, 6)
                    Text(left).font(.system(size: 11.5)).foregroundStyle(Palette.ink2).monospacedDigit().padding(.top, 2)
                    HStack(spacing: 5) {
                        Image(systemName: "play").font(.system(size: 10, weight: .bold))
                        Text("Resume")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Color.primary, in: Capsule())
                    .padding(.top, 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 144)
            .padding(16)
            .background { NowReadingBackground(color: book.color) }
            .offset(y: hover.isOn ? -2 : 0)
            .animation(.easeOut(duration: 0.15), value: hover.isOn)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help("Open \u{201C}\(book.displayTitle)\u{201D}")
    }
}

/// Paper with a wash of the cover's colour from the top-left corner, as in the design.
private struct NowReadingBackground: View {
    var color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        shape
            .fill(Palette.surface)
            .overlay {
                shape.fill(RadialGradient(colors: [color.opacity(0.22), color.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 420))
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
            .shadow(color: Color(red: 70 / 255, green: 45 / 255, blue: 20 / 255).opacity(0.08), radius: 15, y: 10)
    }
}

// MARK: - Grid

/// A shelf's books: covers filling equal columns (six on a wide page), with the title, author and state under each.
private struct BookGrid: View {
    var books: [Book]
    var onOpen: (ID) -> Void
    @Environment(\.pageWidth) private var width

    var body: some View {
        // `pageWidth` is the whole column; the page pads it by 28 (18 when narrow) on each side.
        let inner = max(200, min(width, 1140) - (width < 700 ? 36 : 56))
        let spacing: CGFloat = width < 700 ? 16 : 22
        let columns = max(2, min(6, Int((inner + spacing) / (140 + spacing))))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns), alignment: .leading, spacing: 26) {
            ForEach(books) { book in
                BookTile(book: book) { onOpen(book.id) }
            }
        }
    }
}

private struct BookTile: View {
    var book: Book
    var onOpen: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                LiftingCover(book: book, hover: hover)
                    .padding(.bottom, 12)
                Text(book.displayTitle).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(book.author.isEmpty ? " " : book.author).font(.system(size: 12)).foregroundStyle(Palette.ink2).lineLimit(1).padding(.top, 2)
                BookStatePill(book: book).padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
        .help(book.displayTitle + (book.author.isEmpty ? "" : " \u{2014} \(book.author)"))
    }
}

/// The cover over a soft ground shadow; it lifts and tips on hover. Only this view reads the hover.
private struct LiftingCover: View {
    var book: Book
    var hover: HoverState

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 60 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 60))
                    .scaleEffect(x: 1, y: 0.2)
                    .frame(height: 70)
                    .padding(.horizontal, 8)
                    .offset(y: 35 - 1)
            }
            .overlay(alignment: .bottom) {
                BookCover(book: book)
                    .offset(y: hover.isOn ? -4 : 0)
                    .rotationEffect(.degrees(hover.isOn ? -1 : 0))
                    .animation(.easeOut(duration: 0.2), value: hover.isOn)
            }
    }
}

/// "Want to read", "34% read" or "✓ Finished" under a cover.
private struct BookStatePill: View {
    var book: Book

    var body: some View {
        let (text, fg, bg): (String, Color, Color) = switch book.status {
        case .reading: ("\(book.percent)% read", bookTint, bookTint.opacity(0.15))
        case .want: ("Want to read", Palette.ink2, Color.primary.opacity(0.06))
        case .done: ("\u{2713} Finished", Palette.green, Palette.green.opacity(0.13))
        }
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(bg, in: Capsule())
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
    @State private var showsManage = false
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
            } onManage: {
                showsCategories = false
                showsManage = true
            }
        }
        .sheet(isPresented: $showsManage) { BookCategoriesSheet() }
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
            ProgressBar(value: Double(book.percent), color: bookTint, height: 4)
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
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Notes").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                Text("\(notes.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink2).monospacedDigit()
                Spacer()
                Button("New Reading Note", systemImage: "square.and.pencil", action: onNewNote)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.ink2)
                    .help("New reading note")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)
            if !notes.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3)
                    TextField("Search notes in this book", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onEscape { query = "" }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
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

/// A reading note in the book's list: its title with the page on the right, then when it was edited and a snippet.
private struct BookNoteRow: View {
    var note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(note.displayTitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !note.linkIDs.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "link").font(.system(size: 9, weight: .semibold))
                        Text("\(note.linkIDs.count)")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
                    .help(plural(note.linkIDs.count, "linked note"))
                }
                if let location = note.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(bookTint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            (Text(NoteDates.short(note.editedAt)).fontWeight(.semibold).foregroundStyle(.primary)
                + Text("  " + (note.snippet.isEmpty ? "No additional text" : note.snippet)))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }
}

/// The categories a book can go in, each editable in place from its ⋯ button, a field to make a new one, and
/// Manage Categories….
private struct BookCategoryPicker: View {
    var selection: ID?
    var onPick: (ID?) -> Void
    var onManage: () -> Void

    @Environment(AppStore.self) private var store
    @State private var newName: String?
    @State private var editing: ID?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Category").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).padding(.horizontal, 6).padding(.vertical, 3)
            ForEach(store.bookCategories) { category in
                if editing == category.id {
                    BookCategoryEditor(category: category) { editing = nil }
                } else {
                    PickerCategoryRow(category: category, selected: selection == category.id,
                                      onPick: { onPick(category.id) }, onEdit: { editing = category.id })
                }
            }
            pickerRow("No category", selected: selection == nil) {
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
                    .onEscape { self.newName = nil }
            } else {
                pickerRow("New category\u{2026}", selected: false) {
                    Image(systemName: "plus").font(.system(size: 11))
                } action: { newName = "" }
            }
            pickerRow("Manage Categories\u{2026}", selected: false) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11))
            } action: { onManage() }
        }
        .padding(6)
        .frame(width: 236)
        .animation(.snappy(duration: 0.2), value: editing)
    }
}

private func pickerRow<Icon: View>(_ title: String, selected: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
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

/// A category in the picker: click to choose it; the ⋯ that shows on hover opens its editor.
private struct PickerCategoryRow: View {
    var category: BookCategory
    var selected: Bool
    var onPick: () -> Void
    var onEdit: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        HStack(spacing: 0) {
            pickerRow(category.name, selected: selected) { ColorDot(color: category.color, size: 8) } action: { onPick() }
            Button(action: onEdit) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename, recolour or delete \u{201C}\(category.name)\u{201D}")
            .modifier(HoverOpacity(hover: hover))
        }
        .background { HoverFill(hover: hover, color: Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 6)) }
        .onHover { hover.isOn = $0 }
    }
}

/// Name, colour and delete for one category, in place of its picker row.
private struct BookCategoryEditor: View {
    var category: BookCategory
    var onDone: () -> Void

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var confirmsDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        let count = store.books.count(where: { $0.categoryID == category.id })
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(done)
                .onEscape { done() }
            SwatchPicker(hex: Binding(get: { category.hex }, set: { store.setBookCategoryColor(category.id, hex: $0) }),
                         size: 12, swatches: NoteCategory.palette)
            if confirmsDelete {
                Text(count == 0 ? "Delete \u{201C}\(category.name)\u{201D}?" : "\(plural(count, "book")) will become uncategorized.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { confirmsDelete = false }
                    Spacer()
                    Button("Delete", role: .destructive) { store.deleteBookCategory(category.id) }
                        .foregroundStyle(Palette.red)
                }
                .controlSize(.small)
            } else {
                HStack {
                    Button("Delete\u{2026}", role: .destructive) { confirmsDelete = true }
                        .foregroundStyle(Palette.red)
                    Spacer()
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            name = category.name
            focused = true
        }
    }

    private func done() {
        store.renameBookCategory(category.id, to: name)
        onDone()
    }
}

/// Every book category, empty ones included: rename, recolour, drag to reorder, delete, and add new ones.
struct BookCategoriesSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var deleting: BookCategory?
    @FocusState private var newFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Book Categories").font(.system(size: 20, weight: .bold))
                    Text("The sections of your library. Drag to reorder.").font(.system(size: 12.5)).foregroundStyle(Palette.ink2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            List {
                ForEach(store.bookCategories) { category in
                    BookCategoryManageRow(category: category) { deleting = category }
                }
                .onMove(perform: move)
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink3).frame(width: 18)
                    TextField("New category", text: $newName)
                        .textFieldStyle(.plain)
                        .focused($newFocused)
                        .onSubmit(add)
                }
                .font(.system(size: 13))
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 220)

            Divider()
            HStack {
                Text("\(store.bookCategories.count) \(store.bookCategories.count == 1 ? "category" : "categories")")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 440)
        .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { store.deleteBookCategory(deleting.id) }
            }
        } message: {
            let n = store.books.count(where: { $0.categoryID == deleting?.id })
            Text("\(plural(n, "book")) will become uncategorized.")
        }
    }

    private func add() {
        if store.addBookCategory(name: newName) != nil { newName = "" }
        newFocused = true
    }

    private func move(_ from: IndexSet, _ to: Int) {
        let list = store.bookCategories
        guard let source = from.first else { return }
        store.moveBookCategory(list[source].id, before: to < list.count ? list[to].id : nil)
    }
}

private struct BookCategoryManageRow: View {
    var category: BookCategory
    var onDelete: () -> Void

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var choosingColor = false
    @State private var hover = HoverState()
    @FocusState private var focused: Bool

    var body: some View {
        let count = store.books.count(where: { $0.categoryID == category.id })
        HStack(spacing: 10) {
            Button { choosingColor = true } label: {
                ColorDot(color: category.color, size: 12).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Colour")
            .popover(isPresented: $choosingColor, arrowEdge: .bottom) {
                SwatchPicker(hex: Binding(get: { category.hex }, set: { hex in
                    store.setBookCategoryColor(category.id, hex: hex)
                    choosingColor = false
                }), size: 16, swatches: NoteCategory.palette)
                .padding(10)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
            Text(plural(count, "book")).font(.system(size: 12)).foregroundStyle(Palette.ink3).monospacedDigit()
            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Palette.ink2).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete category")
            .modifier(HoverOpacity(hover: hover, forced: focused))
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
        .onHover { hover.isOn = $0 }
        .onAppear { name = category.name }
        .onChange(of: category.name) { if !focused { name = category.name } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = category.name } else { store.renameBookCategory(category.id, to: name) }
    }
}
