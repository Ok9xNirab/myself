import SwiftUI
import UniformTypeIdentifiers

/// A note's icon and cover (the v2 design's page header): choices, the views that draw them, and the pickers.
enum NoteIcon {
    /// The symbols the icon picker offers, from the design (Sigma, Book, Flask, Code, Atom, Bulb, Pen, Globe,
    /// Chart, Star, Heart, Bolt).
    static let symbols = ["sum", "book.closed", "flask", "chevron.left.forwardslash.chevron.right", "atom", "lightbulb",
                          "pencil", "globe", "chart.bar", "star", "heart", "bolt"]

    /// Icon gradients (light, dark end), from the design's `COL`.
    static let colors: [(UInt32, UInt32)] = [(0x45C47F, 0x1F7A45), (0x5A92FF, 0x1D5AD6), (0xA27BFF, 0x6D3FD6), (0xFFB14A, 0xE06A00),
                                             (0xFF7A7A, 0xD63A3A), (0x3CC4D4, 0x11808E), (0xD4A06A, 0x8F5A26), (0x5B5F6B, 0x26282F)]

    static func gradient(_ index: Int?) -> LinearGradient {
        let pair = colors[min(max(index ?? 0, 0), colors.count - 1)]
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
    }
}

/// An image from the note image store (an uploaded icon or cover), loaded off the main thread.
struct StoredNoteImage<Placeholder: View>: View {
    var name: String
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder
    @Environment(AppStore.self) private var store
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: name) { await load() }
    }

    private func load() async {
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

/// A note's icon at any size: its uploaded image, or its symbol on a gradient tile. Nothing when it has neither.
struct NoteIconView: View {
    var icon: String?
    var color: Int?
    var image: String?
    var size: CGFloat

    init(icon: String?, color: Int?, image: String?, size: CGFloat) {
        (self.icon, self.color, self.image, self.size) = (icon, color, image, size)
    }

    init(note: Note, size: CGFloat) { self.init(icon: note.icon, color: note.iconColor, image: note.iconImage, size: size) }
    init(summary: NoteSummary, size: CGFloat) { self.init(icon: summary.icon, color: summary.iconColor, image: summary.iconImage, size: size) }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.29, style: .continuous) }

    var body: some View {
        if let image {
            StoredNoteImage(name: image, contentMode: .fill) { shape.fill(Palette.surface2) }
                .frame(width: size, height: size)
                .clipShape(shape)
        } else if let icon {
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(NoteIcon.gradient(color), in: shape)
        }
    }
}

/// The cover band across the top of a note: its uploaded image or gradient.
struct NoteCoverView: View {
    var note: Note

    var body: some View {
        if let name = note.coverImage {
            StoredNoteImage(name: name, contentMode: .fill) { Palette.surface2 }
        } else {
            MeshGradientView(colors: (note.cover.flatMap(CoverGradient.init(rawValue:)) ?? .meadow).colors)
        }
    }
}

// MARK: Header

/// The top of a note in the editor: the cover (with Change / Shuffle / Remove on hover), the icon overlapping its
/// bottom edge, and Add icon / Add cover buttons while either is missing. Both pickers open from here.
struct NoteLookHeader: View {
    var note: Note
    /// How far the cover reaches past the text column on each side.
    var bleed: CGFloat
    var editable: Bool
    /// Whether the pointer is over the top of the note (header and title), which shows Add icon / Add cover.
    var hover: HoverState
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var showsCoverPicker = false
    @State private var showsIconPicker = false

    static let coverHeight: CGFloat = 190
    static let iconSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.hasCover {
                NoteCoverView(note: note)
                    .frame(height: Self.coverHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                    .padding(.horizontal, -bleed)
                    .overlay(alignment: .bottomTrailing) {
                        if editable { coverActions.padding(.trailing, 14 - bleed).padding(.bottom, 12) }
                    }
                    .popover(isPresented: $showsCoverPicker, arrowEdge: .bottom) { NoteCoverPicker(note: note) }
            }
            if note.hasIcon {
                iconButton
                    .padding(.top, note.hasCover ? -Self.iconSize / 2 : 0)
            }
            if editable && (!note.hasIcon || !note.hasCover) {
                HStack(spacing: 4) {
                    if !note.hasIcon {
                        addButton("Add icon", "face.smiling") {
                            store.setNoteLook(note.id, actionName: "Add Icon", undoManager: undoManager) {
                                $0.icon = NoteIcon.symbols.randomElement()
                                $0.iconColor = Int.random(in: 0..<NoteIcon.colors.count)
                            }
                        }
                    }
                    if !note.hasCover {
                        addButton("Add cover", "photo") {
                            store.setNoteLook(note.id, actionName: "Add Cover", undoManager: undoManager) {
                                $0.cover = CoverGradient.allCases.randomElement()?.rawValue
                            }
                        }
                    }
                }
                .padding(.top, note.hasIcon ? 10 : 0)
                .padding(.leading, -8)
                .modifier(HoverOpacity(hover: hover))
            }
        }
        .padding(.bottom, note.hasIcon || note.hasCover ? 14 : 4)
    }

    private var iconButton: some View {
        Button { if editable { showsIconPicker = true } } label: {
            NoteIconView(note: note, size: Self.iconSize)
                .background {
                    RoundedRectangle(cornerRadius: Self.iconSize * 0.29 + 4, style: .continuous)
                        .fill(Palette.surface)
                        .padding(-4)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
        }
        .buttonStyle(.plain)
        .help(editable ? "Change icon" : "")
        .popover(isPresented: $showsIconPicker, arrowEdge: .bottom) { NoteIconPicker(note: note) }
    }

    private var coverActions: some View {
        HStack(spacing: 2) {
            Button { showsCoverPicker = true } label: {
                Label("Change cover", systemImage: "photo").padding(.horizontal, 10)
            }
            Button {
                let others = CoverGradient.allCases.filter { $0.rawValue != note.cover }
                store.setNoteLook(note.id, actionName: "Change Cover", undoManager: undoManager) {
                    $0.cover = others.randomElement()?.rawValue
                    $0.coverImage = nil
                }
            } label: {
                Image(systemName: "shuffle").frame(width: 30)
            }
            .help("Random cover")
            Button {
                store.setNoteLook(note.id, actionName: "Remove Cover", undoManager: undoManager) { ($0.cover, $0.coverImage) = (nil, nil) }
            } label: {
                Image(systemName: "trash").frame(width: 30)
            }
            .help("Remove cover")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Color(hex: 0x1D1D1F))
        .frame(height: 28)
        .padding(3)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 7, y: 4)
        .modifier(HoverOpacity(hover: hover, forced: showsCoverPicker))
    }

    private func addButton(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Pickers

private struct PickerChrome<Content: View>: View {
    @Binding var tab: Int
    var tabs: [String]
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(tabs.indices, id: \.self) { Text(tabs[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 4)
            content
        }
        .padding(12)
        .frame(width: 360)
    }
}

/// Every SF Symbol (`SymbolCatalog`), searchable by name and keyword and filtered by category; the design's
/// twelve come first while nothing is searched or filtered.
private struct SymbolGrid: View {
    var selected: String?
    var onPick: (String) -> Void
    @State private var catalog: SymbolCatalog?
    @State private var query = ""
    @State private var category: String?

    var body: some View {
        let shown = symbols
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                NoteSearchField(placeholder: "Search \(catalog.map { $0.names.count.formatted() } ?? "") symbols", text: $query)
                if let catalog, !catalog.categories.isEmpty {
                    Menu {
                        Picker("Category", selection: $category) {
                            Label("All", systemImage: "square.grid.2x2").tag(String?.none)
                            Divider()
                            ForEach(catalog.categories) { Label($0.title, systemImage: $0.icon).tag(String?.some($0.id)) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: catalog.categories.first { $0.id == category }?.icon ?? "line.3.horizontal.decrease")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(catalog.categories.first { $0.id == category }?.title ?? "Category")
                }
            }
            .padding(.top, 10)
            pickerHeading(category.flatMap { id in catalog?.categories.first { $0.id == id }?.title } ?? (query.isEmpty ? "Symbol" : "\(shown.count.formatted()) found"))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(shown, id: \.self) { symbol in
                        let on = selected == symbol
                        Button { onPick(symbol) } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(on ? Palette.surface : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(on ? Color.primary : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                if shown.isEmpty {
                    Text("No symbols match \u{201C}\(query)\u{201D}")
                        .font(.system(size: 12.5)).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .frame(height: 220)
        }
        .task { if catalog == nil { catalog = await SymbolCatalog.load() } }
    }

    private var symbols: [String] {
        guard let catalog, !catalog.names.isEmpty else {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return NoteIcon.symbols.filter { q.isEmpty || $0.contains(q) }
        }
        let found = catalog.symbols(in: category, matching: query)
        guard query.isEmpty, category == nil else { return found }
        // The design's set first, then the rest in the SF Symbols order.
        let suggested = NoteIcon.symbols + (selected.map { [$0] } ?? [])
        return Array(NSOrderedSet(array: suggested + found)) as? [String] ?? found
    }
}

private func pickerHeading(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .bold))
        .kerning(0.6)
        .textCase(.uppercase)
        .foregroundStyle(Palette.ink2)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.leading, 2)
}

/// Drop or choose an image file (the pickers' Upload tab).
private struct ImageDropArea: View {
    var title: String
    var detail: String
    var onImage: (Data) -> Void
    @State private var choosing = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "photo.badge.plus").font(.system(size: 22)).foregroundStyle(Palette.ink2)
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.ink2)
            Button("Choose Image\u{2026}") { choosing = true }
                .controlSize(.small)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Color.primary.opacity(0.16)))
        .padding(.top, 10)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return false }
            onImage(data)
            return true
        } isTargeted: { targeted = $0 }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { onImage(data) }
        }
    }
}

struct NoteCoverPicker: View {
    var note: Note
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var tab = 0
    @State private var failed = false

    var body: some View {
        PickerChrome(tab: $tab, tabs: ["Gradients", "Upload"]) {
            if tab == 0 {
                pickerHeading("Gradients")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(CoverGradient.allCases) { gradient in
                        let on = note.coverImage == nil && note.cover == gradient.rawValue
                        Button {
                            store.setNoteLook(note.id, actionName: "Change Cover", undoManager: undoManager) {
                                ($0.cover, $0.coverImage) = (gradient.rawValue, nil)
                            }
                        } label: {
                            MeshGradientView(colors: gradient.colors)
                                .frame(height: 52)
                                .overlay(alignment: .bottomLeading) {
                                    Text(gradient.title)
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.55))
                                        .padding(.leading, 6).padding(.bottom, 4)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(2)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(gradient.title) cover")
                    }
                }
            } else {
                ImageDropArea(title: "Drop an image here", detail: failed ? "That file isn\u{2019}t an image MySelf can read." : "JPG, PNG or HEIC. Wide images work best.") { data in
                    guard let name = store.addNoteLookImage(data, icon: false) else { failed = true; return }
                    failed = false
                    store.setNoteLook(note.id, actionName: "Change Cover", undoManager: undoManager) { $0.coverImage = name }
                }
            }
        }
        .onAppear { if note.coverImage != nil { tab = 1 } }
    }
}

struct NoteIconPicker: View {
    var note: Note
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var failed = false

    var body: some View {
        PickerChrome(tab: $tab, tabs: ["Symbols", "Upload"]) {
            if tab == 0 {
                SymbolGrid(selected: note.iconImage == nil ? note.icon : nil) { symbol in
                    store.setNoteLook(note.id, actionName: "Change Icon", undoManager: undoManager) {
                        ($0.icon, $0.iconImage) = (symbol, nil)
                        if $0.iconColor == nil { $0.iconColor = 0 }
                    }
                }
                pickerHeading("Color")
                HStack(spacing: 8) {
                    ForEach(NoteIcon.colors.indices, id: \.self) { index in
                        let on = (note.iconColor ?? 0) == index
                        Button {
                            store.setNoteLook(note.id, actionName: "Change Icon", undoManager: undoManager) {
                                $0.iconColor = index
                                if $0.icon == nil { $0.icon = NoteIcon.symbols[0] }
                                $0.iconImage = nil
                            }
                        } label: {
                            Circle().fill(NoteIcon.gradient(index))
                                .frame(width: 28, height: 28)
                                .padding(2)
                                .overlay(Circle().strokeBorder(on ? Color.primary.opacity(0.4) : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ImageDropArea(title: "Drop an image", detail: failed ? "That file isn\u{2019}t an image MySelf can read." : "Square works best · PNG, JPG or HEIC") { data in
                    guard let name = store.addNoteLookImage(data, icon: true) else { failed = true; return }
                    failed = false
                    store.setNoteLook(note.id, actionName: "Change Icon", undoManager: undoManager) { $0.iconImage = name }
                }
            }
            HStack {
                Button("Remove icon") {
                    store.setNoteLook(note.id, actionName: "Remove Icon", undoManager: undoManager) {
                        ($0.icon, $0.iconColor, $0.iconImage) = (nil, nil, nil)
                    }
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.red)
                Spacer()
                Text("Shown in lists and links").font(.system(size: 11.5)).foregroundStyle(Palette.ink2)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Divider() }
            .padding(.top, 12)
        }
        .onAppear { if note.iconImage != nil { tab = 1 } }
    }
}
