import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Loads the images in note image blocks. The editor shows a downsampled copy (cached, so scrolling a long
/// note doesn't decode full-size photos again); the viewer loads the full image.
enum NoteImages {
    /// Longest side of the editor's copy, in pixels: the page is at most 780 pt wide on a 2× display.
    private static let previewPixels = 1800
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImage>()

    nonisolated static func preview(at url: URL) -> CGImage? {
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    nonisolated static func full(at url: URL) -> PlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    /// The data and file extension of an image file the user picked or dropped, or nil if it isn't an image.
    static func read(_ url: URL) -> (data: Data, ext: String)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: url) else { return nil }
        return (data, url.pathExtension)
    }

    #if os(macOS)
    /// An image on the pasteboard (a copied image file, or image data such as a screenshot) as file data.
    /// Returns nil when the pasteboard holds text, so pasting text is left to the text view.
    static func fromPasteboard(_ pasteboard: NSPasteboard) -> (data: Data, ext: String)? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = read(url) {
            return image
        }
        guard pasteboard.string(forType: .string) == nil else { return nil }
        if let png = pasteboard.data(forType: .png) { return (png, "png") }
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return (png, "png")
    }
    #endif
}

/// The full-size image from a note, fitted to the window, with zoom (⌘+ ⌘− ⌘0, pinch, or double-click). Esc closes it.
/// On macOS it's a window of its own (`NoteImageViewer.windowID`); elsewhere a sheet.
struct NoteImageViewer: View {
    static let windowID = "note-image"

    var name: String

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var image: PlatformImage?
    @State private var failed = false
    /// nil fits the image to the window.
    @State private var zoom: CGFloat?
    @State private var fitScale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private static let steps: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    private var scale: CGFloat { zoom ?? fitScale }

    var body: some View {
        Group {
            if let image {
                viewer(image)
            } else if failed {
                EmptyStateView(systemImage: "photo", title: "Image not found", subtitle: "It may not have synced to this Mac yet.")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface2)
        .navigationTitle("Image")
        .toolbar { toolbar }
        .background {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task(id: name) { await load() }
    }

    private func viewer(_ image: PlatformImage) -> some View {
        GeometryReader { geo in
            let size = image.size
            let shown = scale * pinch
            ScrollView([.horizontal, .vertical]) {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width * shown, height: size.height * shown)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    .onTapGesture(count: 2) { zoom = zoom == nil ? 1 : nil }
            }
            .scrollIndicators(.automatic)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { zoom = clamp(scale * $0.magnification) }
            )
            .onChange(of: geo.size, initial: true) {
                guard size.width > 0, size.height > 0 else { return }
                // Fit, but never blow a small image up past its real size.
                fitScale = min(geo.size.width / size.width, geo.size.height / size.height, 1)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { step(-1) }
                .keyboardShortcut("-")
                .disabled(image == nil || scale <= Self.steps.first!)
            Text("\(Int((scale * 100).rounded()))%")
                .monospacedDigit()
                .frame(minWidth: 44)
                .foregroundStyle(Palette.ink2)
            Button("Zoom In", systemImage: "plus.magnifyingglass") { step(1) }
                .keyboardShortcut("+")
                .disabled(image == nil || scale >= Self.steps.last!)
            Button("Fit", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left") { zoom = nil }
                .keyboardShortcut("0")
                .help("Fit to window (⌘0)")
                .disabled(image == nil || zoom == nil)
            Button("Actual Size", systemImage: "1.magnifyingglass") { zoom = 1 }
                .help("Actual size")
                .disabled(image == nil || zoom == 1)
            #if !os(macOS)
            Button("Done") { dismiss() }
            #endif
        }
    }

    private func step(_ direction: Int) {
        let next = direction > 0 ? Self.steps.first { $0 > scale + 0.001 } : Self.steps.last { $0 < scale - 0.001 }
        if let next { withAnimation(.snappy(duration: 0.2)) { zoom = next } }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.steps.first!), Self.steps.last!)
    }

    private func load() async {
        while !Task.isCancelled {
            switch store.sync.imageState(name) {
            case .ready(let url):
                image = NoteImages.full(at: url)
                failed = image == nil
                return
            case .missing:
                failed = true
                return
            case .downloading:
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
