import SwiftUI

/// A short message shown at the bottom of the main window, such as "iCloud synced" after Sync Now (`AppStore.showToast`).
struct Toast: Equatable {
    var id = UUID()
    var text: String
    var systemImage: String
    /// Shows a spinner instead of the icon (a sync in progress).
    var isProgress = false
    var isError = false
}

/// Draws `store.toast` as a small capsule that slides up from the bottom edge.
struct ToastOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if let toast = store.toast {
                HStack(spacing: 8) {
                    if toast.isProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: toast.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(toast.isError ? Palette.red : Palette.green)
                    }
                    Text(toast.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                }
                .frame(maxWidth: 420)
                .padding(.bottom, 22)
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.smooth(duration: 0.25), value: store.toast)
    }
}
