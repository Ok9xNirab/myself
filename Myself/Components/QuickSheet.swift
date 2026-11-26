import SwiftUI

/// The v2 quick-add sheet layout shared by the task and University sheets: a large title area with a close
/// button, labelled rows separated by hairlines, and a footer with the keyboard hint, Cancel and a dark Add/Save
/// pill. ⌘↩ saves and Esc cancels.
struct QuickSheet<Leading: View, Header: View, Rows: View>: View {
    @Environment(\.dismiss) private var dismiss
    var isNew: Bool
    /// The primary button's title for a new record ("Add class").
    var addTitle: String
    var canSave: Bool
    var onSave: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var header: Header
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 6) { header }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink2).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 26)
            Divider().opacity(0.6)
            VStack(spacing: 0) { rows }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            footer
        }
        #if os(macOS)
        .frame(width: 580)
        #endif
        .background(Palette.surface)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            HStack(spacing: 4) {
                KeyCap("\u{2318}"); KeyCap("\u{21A9}")
                Text("to \(isNew ? "add" : "save") \u{00B7}")
                KeyCap("esc")
                Text("to cancel")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink2)
            #endif
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.primary.opacity(0.06), in: Capsule())
            Button(action: save) {
                Label(isNew ? addTitle : "Save", systemImage: isNew ? "plus" : "checkmark")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Color.primary.opacity(canSave ? 1 : 0.3), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.surface2.opacity(0.6))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private func save() {
        guard canSave else { return }
        onSave()
        dismiss()
    }
}

extension QuickSheet where Leading == EmptyView {
    init(isNew: Bool, addTitle: String, canSave: Bool, onSave: @escaping () -> Void,
         @ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows) {
        self.init(isNew: isNew, addTitle: addTitle, canSave: canSave, onSave: onSave,
                  leading: { EmptyView() }, header: header, rows: rows)
    }
}

/// The sheet's big title field.
struct SheetTitleField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .bold))
            .onSubmit(onSubmit)
    }
}

/// A sheet row: an icon and label on the left, the control on the right, a hairline below unless `last`.
struct SheetRow<Content: View>: View {
    var title: String
    var systemImage: String
    var last = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink2)
                .frame(width: 104, alignment: .leading)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5) } }
    }
}

/// A plain text field on a soft rounded well, for a sheet row.
struct SheetTextField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    var maxWidth: CGFloat = 280

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

/// A rounded chip that's on or off (the sheets' Space, Due and Course choices).
struct ChoiceChip<Label: View>: View {
    var isOn: Bool
    var tint: Color
    var dashed = false
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isOn ? tint : .primary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(isOn ? tint.opacity(0.12) : Palette.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isOn ? tint : Color.primary.opacity(dashed ? 0.2 : 0.08),
                                           style: StrokeStyle(lineWidth: isOn ? 1.5 : 1, dash: dashed && !isOn ? [3, 3] : []))
                }
                .shadow(color: .black.opacity(isOn ? 0 : 0.04), radius: 1, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Quick date chips ("Tomorrow Fri", "In a week Thu 3") and a Pick date chip with a calendar popover.
/// `optional` lets a chip be switched off again (no date).
struct DateChips: View {
    @Binding var date: Date?
    var options: [(title: String, days: Int)]
    var optional = true
    var tint: Color = Palette.blue
    @State private var picking = false

    var body: some View {
        let day = date.map(Day.calendar.startOfDay(for:))
        let quick = options.contains { Day.offset($0.days) == day }
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(options, id: \.title) { option in
                let value = Day.offset(option.days)
                let on = day == value
                ChoiceChip(isOn: on, tint: tint) {
                    if on { if optional { date = nil } } else { date = value }
                } label: {
                    Text(option.title)
                    Text(value.formatted(option.days >= 7 ? .dateTime.weekday(.abbreviated).day() : .dateTime.weekday(.abbreviated)))
                        .foregroundStyle(Palette.ink2).fontWeight(.medium)
                }
            }
            ChoiceChip(isOn: date != nil && !quick, tint: tint, dashed: date == nil || quick) {
                picking = true
            } label: {
                Image(systemName: "calendar").font(.system(size: 11))
                Text(date != nil && !quick ? date!.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) : "Pick date")
            }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                DatePicker("Date", selection: Binding(get: { date ?? Day.offset(0) }, set: { date = Day.calendar.startOfDay(for: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }
        }
    }
}

/// Segmented tabs whose options each carry an icon in their own colour (Priority, exam Type).
struct TintedTabs<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String
    var systemImage: (Option) -> String
    var color: (Option) -> Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = option } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage(option)).font(.system(size: 11, weight: .semibold)).foregroundStyle(color(option))
                        Text(title(option))
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(on ? Color.primary : Palette.ink2)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.surface)
                                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .fixedSize()
    }
}

/// The sheet's square done checkbox, also used as the header's leading control.
struct SheetCheckbox: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor : Palette.ink3, lineWidth: 1.6)
                .background(isOn ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) } }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Mark as not done" : "Mark as done")
    }
}

/// The header's leading icon tile, in the record's colour.
struct SheetIcon: View {
    var systemImage: String
    var color: Color

    var body: some View {
        CardIcon(systemImage: systemImage, tint: color, size: 30)
            .padding(.top, 1)
    }
}

#if os(macOS)
struct KeyCap: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
#endif
