import SwiftUI

/// Solo-company projects, each on a four-column Kanban board (the v2 Product Dev screen): the project's header with
/// its switcher, then glass columns of cards over a dotted canvas. Cards drag between and within columns.
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
                ProjectHeader(project: project, onEdit: { editingProduct = project }, onDelete: { deletingProduct = project },
                              onNew: newProduct)
                KanbanBoard(product: project, onEdit: { editingCard = $0 }) { status in
                    editingCard = store.newCard(in: project.id, status: status)
                }
            } else {
                SpaceHeader(page: .products)
                VStack(spacing: 14) {
                    EmptyStateView(systemImage: "shippingbox", title: "No projects yet", subtitle: "Create your first product to start a board.")
                    Button("New Project", systemImage: "plus", action: newProduct)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            }
        }
        .toolbar {
            if let project {
                ToolbarItem(placement: .primaryAction) {
                    Button("Card", systemImage: "plus") { editingCard = store.newCard(in: project.id, status: .backlog) }
                        .labelStyle(.titleAndIcon)
                        .help("New card in Backlog")
                }
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
}

private enum BoardTone {
    static let soft = Color.primary.opacity(0.045)
    static let line = Color.primary.opacity(0.07)
    static let redText = Color.dynamic(light: 0xC62828, dark: 0xFF7B7B)
    static let orangeText = Color.dynamic(light: 0xB25D00, dark: 0xFFAE5C)
    static let orange = Color.dynamic(light: 0xF5871F, dark: 0xFFAE5C)
    static let blueText = Color.dynamic(light: 0x1D5AD6, dark: 0x7AA6FF)
    static let greenText = Color.dynamic(light: 0x1F8A4F, dark: 0x5FD393)
}

extension KanbanStatus {
    /// The column's chip colours (the design's `c-gy`, `c-bl`, `c-or`, `c-gr`).
    fileprivate var chip: (text: Color, fill: Color) {
        switch self {
        case .backlog: (Palette.ink2, BoardTone.soft)
        case .inProgress: (BoardTone.blueText, Palette.blue.opacity(0.1))
        case .review: (BoardTone.orangeText, BoardTone.orange.opacity(0.14))
        case .done: (BoardTone.greenText, Palette.green.opacity(0.13))
        }
    }

    fileprivate var boardTitle: String { self == .inProgress ? "In progress" : title }
}

extension Priority {
    /// The card's priority chip and stripe: High red, Medium orange, Low grey.
    fileprivate var chip: (text: Color, fill: Color, stripe: Color) {
        switch self {
        case .high: (BoardTone.redText, Palette.red.opacity(0.12), Palette.red)
        case .medium: (BoardTone.orangeText, BoardTone.orange.opacity(0.14), BoardTone.orange)
        case .low: (Palette.ink2, BoardTone.soft, Palette.ink3)
        }
    }
}

/// A design `.chip`.
private struct BoardChip: View {
    var text: String
    var color: Color
    var fill: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
    }
}

// MARK: Header

/// The project's icon tile, name, "tagline · 5 open · 25% shipped", edit / delete on hover, and the project switcher.
private struct ProjectHeader: View {
    @Environment(AppStore.self) private var store
    var project: Product
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onNew: () -> Void
    @State private var hover = HoverState()

    var body: some View {
        let cards = store.cards.filter { $0.productID == project.id }
        let done = cards.filter { $0.status == .done }.count
        let shipped = cards.isEmpty ? 0 : Int((100 * Double(done) / Double(cards.count)).rounded())
        let detail = ([project.tagline].filter { !$0.isEmpty } + ["\(cards.count - done) open", "\(shipped)% shipped"])
            .joined(separator: " \u{00B7} ")

        HStack(alignment: .center, spacing: 14) {
            Image(systemName: Page.products.systemImage)
                .symbolVariant(.fill)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(project.color.gradient)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 8)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(project.name).font(.system(size: 30, weight: .heavy)).kerning(-0.9).lineLimit(1)
                    HStack(spacing: 0) {
                        headerButton("pencil", "Edit Project", action: onEdit)
                        headerButton("trash", "Delete Project", action: onDelete)
                    }
                    .modifier(HoverOpacity(hover: hover, off: 0.0))
                }
                Text(detail).font(.system(size: 13.5)).foregroundStyle(.primary.opacity(0.75)).lineLimit(1)
            }
            .onHover { hover.isOn = $0 }
            Spacer(minLength: 12)
            ColorTabs(items: store.products, selection: project.id, title: \.name, color: \.color,
                      onSelect: { store.selectedProduct = $0 }, addHelp: "New Project", onAdd: onNew)
                .padding(3)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(BoardTone.line, lineWidth: 0.5))
                .fixedSize()
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func headerButton(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 13)).foregroundStyle(Palette.ink2).frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: Board

/// 4 columns, dropping to 2 then 1 on narrow windows, over a dotted canvas. Each column is only as tall as its cards.
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
        .padding(.vertical, 6)
        .frame(minHeight: 420, alignment: .top)
        .background { DotGrid().padding(.horizontal, -28).padding(.bottom, -56) }
    }
}

/// The board's dotted canvas (`radial-gradient` dots every 18 pt).
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18, r: CGFloat = 1.2
            var path = Path()
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    x += step
                }
                y += step
            }
            context.fill(path, with: .color(.primary.opacity(0.08)))
        }
        .allowsHitTesting(false)
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
            HStack(spacing: 8) {
                BoardChip(text: status.boardTitle, color: status.chip.text, fill: status.chip.fill)
                Text("\(cards.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)

            if cards.isEmpty {
                Text("Drop cards here")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(BoardTone.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            }

            ForEach(cards) { card in
                KanbanCardView(card: card, onEdit: { onEdit(card) })
                    .draggable(card.id)
            }

            Button(action: onAdd) {
                Label("Add card", systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a card to \(status.boardTitle)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.1)) : AnyShapeStyle(.regularMaterial))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : BoardTone.line, lineWidth: isTargeted ? 1.5 : 0.5)
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
    @State private var hover = HoverState()
    /// A card dragged over this one lands just above it.
    @State private var isTargeted = false

    var body: some View {
        let labels = card.labelIDs.compactMap(store.label)
        let done = card.status == .done
        let pri = card.priority.chip
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(done ? Palette.ink3 : pri.stripe).frame(width: 28, height: 3)
                .padding(.bottom, 8)
            Text(card.title)
                .font(.system(size: 13.5, weight: .semibold))
                .strikethrough(done)
                .foregroundStyle(done ? Palette.ink2 : .primary)
                .fixedSize(horizontal: false, vertical: true)
            if !card.desc.isEmpty && !done {
                Text(card.desc)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
                    .lineSpacing(1.5)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                BoardChip(text: card.priority.title, color: pri.text, fill: pri.fill)
                dueChip(done: done)
                ForEach(labels) { LabelChip(label: $0) }
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            RowActions(hover: hover, onEdit: onEdit) {
                withAnimation(.snappy) { store.deleteCard(card.id, undoManager: undoManager) }
            }
            .padding(5)
        }
        .background { CardSurface(hover: hover) }
        .overlay(alignment: .top) {
            if isTargeted {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -5.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hover.isOn = $0 }
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit Card…", systemImage: "pencil", action: onEdit)
            Menu("Move To", systemImage: "arrow.right") {
                ForEach(KanbanStatus.allCases.filter { $0 != card.status }) { status in
                    Button(status.boardTitle) { withAnimation(.snappy) { store.moveCard(card.id, to: status, undoManager: undoManager) } }
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

    /// "Shipped" in Done; otherwise "Today", "Tomorrow", "Wed", "Nov 14", "2d overdue" or "No date".
    private func dueChip(done: Bool) -> BoardChip {
        if done { return BoardChip(text: "Shipped", color: BoardTone.greenText, fill: Palette.green.opacity(0.13)) }
        guard let due = card.due, let n = Day.fromToday(due) else {
            return BoardChip(text: "No date", color: Palette.ink2, fill: BoardTone.soft)
        }
        switch n {
        case ..<0: return BoardChip(text: "\(-n)d overdue", color: BoardTone.redText, fill: Palette.red.opacity(0.12))
        case 0: return BoardChip(text: "Today", color: BoardTone.blueText, fill: Palette.blue.opacity(0.1))
        case 1: return BoardChip(text: "Tomorrow", color: Palette.ink2, fill: BoardTone.soft)
        case 2...6: return BoardChip(text: due.formatted(.dateTime.weekday(.abbreviated)), color: Palette.ink2, fill: BoardTone.soft)
        default: return BoardChip(text: due.monthDay, color: Palette.ink2, fill: BoardTone.soft)
        }
    }
}

/// A card's paper, hairline and shadow, lifted on hover: drawn by its own shape, so hovering redraws neither the
/// card nor its content.
private struct CardSurface: View {
    var hover: HoverState

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Palette.surface)
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(BoardTone.line, lineWidth: 0.5) }
            .shadow(color: .black.opacity(hover.isOn ? 0.09 : 0.04), radius: hover.isOn ? 7 : 3, y: hover.isOn ? 3 : 2)
    }
}

// MARK: Sheets

/// Add / edit sheet for a project's name, tagline and colour, in the quick-add style.
private struct ProductSheet: View {
    @Environment(AppStore.self) private var store
    @State var draft: Product
    var undoManager: UndoManager?
    /// Called with the project's ID after saving, so the page can show a new project.
    var onSave: (ID) -> Void
    @FocusState private var focused: Bool

    private var isNew: Bool { store.product(draft.id) == nil }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add project", canSave: !trimmed(draft.name).isEmpty, onSave: save) {
            SheetIcon(systemImage: Page.products.systemImage, color: draft.color)
        } header: {
            SheetTitleField(title: "Name", prompt: "Project name", text: $draft.name)
                .focused($focused)
            TextField("Tagline", text: $draft.tagline, prompt: Text("What it is, in a few words"))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        } rows: {
            SheetRow(title: "Colour", systemImage: "paintpalette", last: true) {
                SwatchPicker(hex: $draft.hex, size: 20).padding(.top, 4)
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

/// Add / edit sheet for a card, in the quick-add style. A card that isn't in the store yet is added on save.
private struct KanbanCardSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: KanbanCard
    var undoManager: UndoManager?
    @FocusState private var focused: Bool

    private var isNew: Bool { !store.cards.contains { $0.id == draft.id } }
    private var canSave: Bool { !trimmed(draft.title).isEmpty }

    var body: some View {
        QuickSheet(isNew: isNew, addTitle: "Add card", canSave: canSave, onSave: save) {
            Capsule().fill(draft.priority.chip.stripe).frame(width: 18, height: 4).padding(.top, 13)
        } header: {
            SheetTitleField(title: "Title", prompt: "What are you building?", text: $draft.title) {
                guard canSave else { return }
                save()
                dismiss()
            }
            .focused($focused)
            TextField("Notes", text: $draft.desc, prompt: Text("Add notes"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
        } rows: {
            SheetRow(title: "Column", systemImage: "rectangle.split.3x1") {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(KanbanStatus.allCases) { s in
                        ChoiceChip(isOn: draft.status == s, tint: s.chip.text) { draft.status = s } label: {
                            Text(s.boardTitle)
                        }
                    }
                }
            }
            SheetRow(title: "Priority", systemImage: "flag") {
                TintedTabs(options: [Priority.low, .medium, .high], selection: $draft.priority, title: \.title,
                           systemImage: { _ in "flag" }, color: { $0.chip.stripe })
            }
            SheetRow(title: "Due", systemImage: "calendar") {
                DateChips(date: $draft.due, options: [("Today", 0), ("Tomorrow", 1), ("In a week", 7)])
            }
            SheetRow(title: "Labels", systemImage: "tag", last: true) {
                LabelPicker(scope: .product, selection: $draft.labelIDs)
            }
        }
        .onAppear { focused = isNew }
    }

    private func save() {
        draft.title = trimmed(draft.title)
        draft.desc = trimmed(draft.desc)
        let known = Set(store.productLabels.map(\.id))
        draft.labelIDs.removeAll { !known.contains($0) }
        store.saveCard(draft, undoManager: undoManager)
    }
}

#Preview {
    ProductsView().environment(AppStore()).frame(width: 1100, height: 700)
}
