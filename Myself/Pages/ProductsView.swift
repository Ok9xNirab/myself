import SwiftUI

/// Solo-company projects, each on a four-column Kanban board. Cards can be dragged between and within columns.
struct ProductsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var editingProduct: Product?
    @State private var editingCard: KanbanCard?
    @State private var deletingProduct: Product?

    var body: some View {
        let project = store.selectedProduct.flatMap(store.product) ?? store.products.first

        PageScroll(maxWidth: nil) {
            if let project {
                ColorTabs(items: store.products, selection: project.id, title: \.name, color: \.color,
                          onSelect: { store.selectedProduct = $0 }, addHelp: "New Project", onAdd: newProduct)
                header(project)
                KanbanBoard(product: project, onEdit: { editingCard = $0 }) { status in
                    editingCard = store.newCard(in: project.id, status: status)
                }
            } else {
                VStack(spacing: 14) {
                    EmptyStateView(systemImage: "shippingbox", title: "No projects yet", subtitle: "Create your first product to start a board.")
                    Button("New Project", systemImage: "plus", action: newProduct)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 80)
            }
        }
        .sheet(item: $editingProduct) { product in
            ProductSheet(draft: product, undoManager: undoManager) { store.selectedProduct = $0 }
        }
        .sheet(item: $editingCard) { card in
            KanbanCardSheet(draft: card, undoManager: undoManager)
        }
        .confirmationDialog("Delete \u{201C}\(deletingProduct?.name ?? "")\u{201D}?",
                            isPresented: Binding(get: { deletingProduct != nil }, set: { if !$0 { deletingProduct = nil } })) {
            Button("Delete Project", role: .destructive) {
                if let deletingProduct { withAnimation { store.deleteProduct(deletingProduct.id, undoManager: undoManager) } }
            }
        } message: {
            let count = deletingProduct.map { p in store.cards.filter { $0.productID == p.id }.count } ?? 0
            Text("Its \(count) \(count == 1 ? "card is" : "cards are") deleted too.")
        }
    }

    private func newProduct() {
        editingProduct = Product(name: "", hex: Palette.swatches[store.products.count % Palette.swatches.count])
    }

    private func header(_ p: Product) -> some View {
        let cards = store.cards.filter { $0.productID == p.id }
        return HStack(spacing: 14) {
            Text(p.name.first.map { String($0).uppercased() } ?? "?")
                .font(.numeral(24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(p.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.name).font(.system(size: 22, weight: .bold))
                    headerButton("pencil", "Edit Project") { editingProduct = p }
                    headerButton("trash", "Delete Project") { deletingProduct = p }
                }
                if !p.tagline.isEmpty {
                    Text(p.tagline).font(.system(size: 13)).foregroundStyle(Palette.ink2)
                }
            }
            Spacer()
            HStack(spacing: 16) {
                stat(cards.count, cards.count == 1 ? "card" : "cards")
                stat(cards.filter { $0.status == .inProgress }.count, "in progress")
                stat(cards.filter { $0.status == .done }.count, "shipped")
            }
        }
    }

    private func headerButton(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 13)).foregroundStyle(Palette.ink3).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        Text("\(Text("\(n)").font(.numeral(18)).foregroundStyle(.primary)) \(label)")
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
    }
}

private extension KanbanStatus {
    var color: Color {
        switch self {
        case .backlog: Palette.ink3
        case .inProgress: Palette.blue
        case .review: Palette.amber
        case .done: Palette.green
        }
    }
}

/// 4 columns, dropping to 2 then 1 on narrow windows. Each column is only as tall as its cards.
private struct KanbanBoard: View {
    var product: Product
    var onEdit: (KanbanCard) -> Void
    var onAdd: (KanbanStatus) -> Void
    @Environment(\.pageWidth) private var width

    var body: some View {
        let count = width >= 900 ? 4 : width >= 560 ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count),
                  alignment: .leading, spacing: 14) {
            ForEach(KanbanStatus.allCases) { status in
                KanbanColumnView(status: status, productID: product.id, onEdit: onEdit) { onAdd(status) }
            }
        }
    }
}

private struct KanbanColumnView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var status: KanbanStatus
    var productID: ID
    var onEdit: (KanbanCard) -> Void
    var onAdd: () -> Void
    @State private var isTargeted = false

    var body: some View {
        let cards = store.cards(of: productID, in: status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.title).font(.system(size: 13, weight: .semibold))
                CountText(value: cards.count)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink3)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a card to \(status.title)")
            }
            .padding(.leading, 6)
            .padding(.top, 2)

            if cards.isEmpty {
                Text("Drop cards here")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            }

            ForEach(cards) { card in
                KanbanCardView(card: card, onEdit: { onEdit(card) })
                    .draggable(card.id)
            }

            Button(action: onAdd) {
                Label("Add card", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        // Dropped on the column itself (not on a card): the card goes to the bottom.
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(.snappy) { store.moveCard(id, to: status, undoManager: undoManager) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct KanbanCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var card: KanbanCard
    var onEdit: () -> Void
    @State private var hovering = false
    /// A card dragged over this one lands just above it.
    @State private var isTargeted = false

    var body: some View {
        let labels = card.labelIDs.compactMap(store.label)
        let done = card.status == .done
        VStack(alignment: .leading, spacing: 6) {
            Badge(text: card.priority.rawValue, systemImage: "flag.fill", color: card.priority.color)
            Text(card.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(done ? Palette.ink2 : .primary)
                .fixedSize(horizontal: false, vertical: true)
            if !card.desc.isEmpty {
                Text(card.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(3)
            }
            if !labels.isEmpty || card.due != nil {
                FlowLayout {
                    ForEach(labels) { LabelChip(label: $0) }
                    // A shipped card isn't overdue; it just shows its date.
                    if done, let due = card.due {
                        Badge(text: due.monthDay, systemImage: "clock", color: Palette.ink3)
                    } else {
                        DueBadge(date: card.due)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // As a background, the priority stripe takes the card's height instead of stretching it.
        .background(alignment: .leading) { Rectangle().fill(card.priority.color).frame(width: 3) }
        .overlay(alignment: .topTrailing) {
            RowActions(isHovering: hovering, onEdit: onEdit) {
                withAnimation(.snappy) { store.deleteCard(card.id, undoManager: undoManager) }
            }
            .padding(4)
        }
        .cardBackground(radius: 9)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .top) {
            if isTargeted {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -5.5)
            }
        }
        .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit Card…", systemImage: "pencil", action: onEdit)
            Menu("Move To", systemImage: "arrow.right") {
                ForEach(KanbanStatus.allCases.filter { $0 != card.status }) { status in
                    Button(status.title) { withAnimation(.snappy) { store.moveCard(card.id, to: status, undoManager: undoManager) } }
                }
            }
            Divider()
            Button("Delete Card", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { store.deleteCard(card.id, undoManager: undoManager) }
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(.snappy) { store.moveCard(id, to: card.status, before: card.id, undoManager: undoManager) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: Sheets

/// Add / edit sheet for a project's name, tagline and colour.
private struct ProductSheet: View {
    @Environment(AppStore.self) private var store
    @State var draft: Product
    var undoManager: UndoManager?
    /// Called with the project's ID after saving, so the page can show a new project.
    var onSave: (ID) -> Void
    @FocusState private var focused: Bool

    private var isNew: Bool { store.product(draft.id) == nil }

    var body: some View {
        EditorForm(title: isNew ? "New Project" : "Edit Project", isNew: isNew, canSave: !trimmed(draft.name).isEmpty, onSave: save) {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("FormFlow"))
                    .focused($focused)
                TextField("Tagline", text: $draft.tagline, prompt: Text("What it is, in a few words"))
            }
            Section("Colour") {
                SwatchPicker(hex: $draft.hex)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        draft.name = trimmed(draft.name)
        draft.tagline = trimmed(draft.tagline)
        store.saveProduct(draft, undoManager: undoManager)
        onSave(draft.id)
    }
}

/// Add / edit sheet for a card. A card that isn't in the store yet is added on save.
private struct KanbanCardSheet: View {
    @Environment(AppStore.self) private var store
    @State var draft: KanbanCard
    var undoManager: UndoManager?
    @State private var hasDue: Bool
    @FocusState private var focused: Bool

    init(draft: KanbanCard, undoManager: UndoManager?) {
        _draft = State(initialValue: draft)
        _hasDue = State(initialValue: draft.due != nil)
        self.undoManager = undoManager
    }

    private var isNew: Bool { !store.cards.contains { $0.id == draft.id } }

    private var due: Binding<Date> {
        Binding(get: { draft.due ?? Day.offset(0) }, set: { draft.due = Day.calendar.startOfDay(for: $0) })
    }

    var body: some View {
        EditorForm(title: isNew ? "New Card" : "Edit Card", isNew: isNew, canSave: !trimmed(draft.title).isEmpty, onSave: save) {
            Section {
                TextField("Title", text: $draft.title, prompt: Text("What are you building?"))
                    .focused($focused)
                TextField("Notes", text: $draft.desc, prompt: Text("Notes (optional)"), axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Picker("Column", selection: $draft.status) {
                    ForEach(KanbanStatus.allCases) { Text($0.title).tag($0) }
                }
                Picker("Priority", selection: $draft.priority) {
                    ForEach(Priority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Due date", isOn: $hasDue.animation())
                if hasDue {
                    DatePicker("Date", selection: due, displayedComponents: .date)
                }
            }
            if !store.labels.isEmpty {
                Section("Labels") {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(store.labels) { label in
                            LabelToggle(label: label, isOn: draft.labelIDs.contains(label.id)) { toggle(label.id) }
                        }
                    }
                }
            }
        }
        .onAppear { focused = isNew }
    }

    private func toggle(_ id: ID) {
        if let i = draft.labelIDs.firstIndex(of: id) { draft.labelIDs.remove(at: i) } else { draft.labelIDs.append(id) }
    }

    private func save() {
        draft.title = trimmed(draft.title)
        draft.desc = trimmed(draft.desc)
        draft.due = hasDue ? (draft.due ?? Day.offset(0)) : nil
        let known = Set(store.labels.map(\.id))
        draft.labelIDs.removeAll { !known.contains($0) }
        store.saveCard(draft, undoManager: undoManager)
    }
}

#Preview {
    ProductsView().environment(AppStore()).frame(width: 1100, height: 700)
}
