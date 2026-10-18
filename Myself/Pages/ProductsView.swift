import SwiftUI

/// Solo-company projects, each on a four-column Kanban board. Cards can be dragged between columns.
struct ProductsView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: ID?

    var body: some View {
        let project = store.products.first { $0.id == selection } ?? store.products.first

        PageScroll(maxWidth: nil) {
            ColorTabs(items: store.products, selection: project?.id, title: \.name, color: \.color) { selection = $0 }

            if let project {
                header(project)
                KanbanBoard(product: project)
            } else {
                EmptyStateView(systemImage: "shippingbox", title: "No projects yet", subtitle: "Create your first product to start a board.")
            }
        }
    }

    private func header(_ p: Product) -> some View {
        let total = p.columns.reduce(0) { $0 + $1.cards.count }
        let shipped = p.column(titled: "Done")?.cards.count ?? 0
        return HStack(spacing: 14) {
            Text(String(p.name.prefix(1)))
                .font(.numeral(24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(p.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(p.name).font(.system(size: 22, weight: .bold))
                    Image(systemName: "pencil").foregroundStyle(Palette.ink3)
                }
                Text(p.tagline).font(.system(size: 13)).foregroundStyle(Palette.ink2)
            }
            Spacer()
            HStack(spacing: 16) {
                stat(total, "cards")
                stat(shipped, "shipped")
            }
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        Text("\(Text("\(n)").font(.numeral(18)).foregroundStyle(.primary)) \(label)")
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
    }

}

/// 4 columns, dropping to 2 then 1 on narrow windows.
private struct KanbanBoard: View {
    var product: Product
    @Environment(\.pageWidth) private var width

    var body: some View {
        let count = width >= 900 ? 4 : width >= 560 ? 2 : 1
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count),
                  alignment: .leading, spacing: 14) {
            ForEach(product.columns) { col in
                KanbanColumnView(column: col, productID: product.id)
            }
        }
    }
}

private struct KanbanColumnView: View {
    @Environment(AppStore.self) private var store
    var column: KanbanColumn
    var productID: ID
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                CountText(value: column.cards.count)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            ForEach(column.cards) { card in
                KanbanCardView(card: card)
                    .draggable(card.id)
            }

            Button {} label: {
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
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(.snappy) { store.moveCard(id, to: column.id, in: productID) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct KanbanCardView: View {
    @Environment(AppStore.self) private var store
    var card: KanbanCard
    @State private var hovering = false

    var body: some View {
        let labels = card.labelIDs.compactMap(store.label)
        HStack(spacing: 0) {
            Rectangle().fill(card.priority.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Badge(text: card.priority.rawValue, systemImage: "flag.fill", color: card.priority.color)
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                        Image(systemName: "trash")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
                    .opacity(hovering ? 1 : 0)
                }
                Text(card.title).font(.system(size: 13, weight: .medium))
                if !card.desc.isEmpty {
                    Text(card.desc).font(.system(size: 12)).foregroundStyle(Palette.ink2)
                }
                if !labels.isEmpty || card.due != nil {
                    FlowLayout {
                        ForEach(labels) { LabelChip(label: $0) }
                        DueBadge(date: card.due)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardBackground(radius: 9)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 6, y: 3)
        .onHover { hovering = $0 }
    }
}

#Preview {
    ProductsView().environment(AppStore()).frame(width: 1100, height: 700)
}
