#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus modifiers, stored in UserDefaults as "keyCode|modifierFlags|label" (an empty string means none).
struct HotKey: Equatable, RawRepresentable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    /// What the key is shown as, e.g. "K" or "Space".
    var key: String

    static let defaultSearch = HotKey(keyCode: UInt16(kVK_ANSI_K), modifiers: [.option, .command], key: "K")

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
        self.key = key
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt16(parts[0]), let flags = UInt(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: flags), key: String(parts[2]))
    }

    var rawValue: String { "\(keyCode)|\(modifiers.rawValue)|\(key)" }

    /// A shortcut from a key press, or nil if it has no ⌘, ⌥ or ⌃ (function keys excepted), which would steal plain typing.
    init?(event: NSEvent) {
        let code = event.keyCode
        let named = Self.keyNames[Int(code)]
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty || Self.functionKeys.contains(Int(code)) else { return nil }
        guard let label = named ?? event.charactersIgnoringModifiers?.uppercased(), !label.isEmpty else { return nil }
        self.init(keyCode: code, modifiers: flags, key: label)
    }

    /// "⌥⌘K"
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        var m = 0
        if modifiers.contains(.command) { m |= cmdKey }
        if modifiers.contains(.option) { m |= optionKey }
        if modifiers.contains(.control) { m |= controlKey }
        if modifiers.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                       kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]

    private static let keyNames: [Int: String] = {
        var names = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
                     kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                     kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"]
        for (i, code) in functionKeys.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()
}

/// The system-wide "Search MySelf" shortcut (Settings › General). It's a Carbon hot key, so it works from any app
/// without Accessibility permission. Pressing it shows Quick Open in a floating panel over whatever app is in front,
/// like Spotlight; MySelf only comes forward once a result is picked.
@Observable
final class SearchShortcut {
    static let shared = SearchShortcut()
    static let defaultsKey = "searchShortcut"

    /// The saved shortcut, nil when turned off.
    private(set) var hotKey: HotKey?
    /// False when another app already uses the shortcut.
    private(set) var isRegistered = false

    @ObservationIgnored private var ref: EventHotKeyRef?
    @ObservationIgnored private weak var store: AppStore?
    @ObservationIgnored private var panel: SearchPanel?
    /// Opens the main window when it has been closed; set by `ContentView`.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    /// Opens a note in its own window; set by `ContentView`.
    @ObservationIgnored var openNoteWindow: ((ID) -> Void)?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? HotKey.defaultSearch.rawValue
        hotKey = HotKey(rawValue: raw)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), searchShortcutPressed, 1, &spec, nil, nil)
    }

    /// Registers the saved shortcut. Called once at launch.
    func start(store: AppStore) {
        self.store = store
        register()
    }

    /// Saves and registers a new shortcut; nil turns it off.
    func set(_ hotKey: HotKey?) {
        self.hotKey = hotKey
        UserDefaults.standard.set(hotKey?.rawValue ?? "", forKey: Self.defaultsKey)
        register()
    }

    /// Lets the Settings recorder see the current shortcut as a normal key press while it records.
    func suspend() { unregister() }

    func resume() { register() }

    private func register() {
        unregister()
        guard let hotKey else { return }
        let id = EventHotKeyID(signature: OSType(0x4D59_534C), id: 1) // "MYSL"
        isRegistered = RegisterEventHotKey(UInt32(hotKey.keyCode), hotKey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        isRegistered = false
    }

    // MARK: Panel

    fileprivate func pressed() {
        if panel?.isVisible == true { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let store else { return }
        let panel = panel ?? SearchPanel()
        self.panel = panel
        // A fresh view each time, so the field starts empty.
        panel.show(QuickOpenView(onClose: { [weak self] in self?.closePanel() }).environment(store))
    }

    func closePanel() {
        panel?.orderOut(nil)
    }

    /// Opens a result picked in the panel, bringing MySelf forward.
    func open(_ target: QuickOpenTarget) {
        guard let store else { return }
        switch target {
        case .page(let page):
            store.go(page)
            showMainWindow()
        case .note(let id):
            activate()
            openNoteWindow?(id)
            // Let the new window appear first, so an older note window isn't the one brought up.
            DispatchQueue.main.async { [weak self] in self?.bringForward(windowPrefix: NoteWindow.id) }
        case .settings:
            showMainWindow()
            store.openSettings(.general)
        }
    }

    private func activate() {
        NSApp.unhide(nil)
        // Picking a result is an explicit request to switch apps, so take focus rather than ask for it.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        activate()
        if NSApp.windows.contains(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            bringForward(windowPrefix: "main")
        } else {
            openMainWindow?()
            bringForward(windowPrefix: "main")
        }
    }

    /// Puts the app's frontmost window whose identifier starts with `windowPrefix` in front of every app. macOS may not
    /// activate MySelf straight away after a non-activating panel, and a window opened meanwhile would stay behind the
    /// app in front, so order it up regardless. A window `openWindow` just created appears a moment later, hence the retries.
    private func bringForward(windowPrefix: String, attempts: Int = 10) {
        let window = NSApp.orderedWindows.first { $0.identifier?.rawValue.hasPrefix(windowPrefix) == true }
            ?? NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(windowPrefix) == true && $0.isVisible }
        guard let window else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.bringForward(windowPrefix: windowPrefix, attempts: attempts - 1)
                }
            }
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }
}

/// Borderless floating panel for the search shortcut. Being non-activating, it takes the keyboard without making
/// MySelf the active app, and it closes when it loses focus (a click elsewhere, or switching apps).
private final class SearchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    func show<Content: View>(_ content: Content) {
        let appearance = UserDefaults.standard.string(forKey: PrefKey.appearance) ?? ""
        self.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
        let host = NSHostingView(rootView: content
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5) })
        contentView = host
        let size = host.fittingSize
        // Centred on the screen with the pointer, a little above the middle, like Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.22 - size.height)
            setFrame(NSRect(origin: origin, size: size), display: false)
        }
        makeKeyAndOrderFront(nil)
        // The view's own `focused = true` runs before the panel is key, so put the cursor in the field once it is.
        DispatchQueue.main.async { [weak self] in
            guard let self, let field = Self.firstTextField(in: host) else { return }
            makeFirstResponder(field)
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }
}

/// Carbon calls this on the main thread for every registered hot key; MySelf only has the one.
nonisolated private func searchShortcutPressed(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated { SearchShortcut.shared.pressed() }
    return noErr
}

/// Settings control: click, then press the new shortcut. Esc cancels, ⌫ turns the shortcut off.
struct ShortcutRecorder: View {
    @State private var shortcut = SearchShortcut.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Type shortcut…" : shortcut.hotKey?.display ?? "None")
                    .monospacedDigit()
                    .foregroundStyle(recording ? Color.accentColor : shortcut.hotKey == nil ? Palette.ink3 : .primary)
                    .frame(minWidth: 96)
            }
            .help(recording ? "Press the new shortcut. Esc cancels, Delete turns it off." : "Click to record a new shortcut")
            if shortcut.hotKey != HotKey.defaultSearch {
                Button("Reset") { stop(); shortcut.set(.defaultSearch) }
                    .help("Use \(HotKey.defaultSearch.display)")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        shortcut.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = Int(event.keyCode)
            let plain = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            if code == kVK_Escape {
                stop()
            } else if plain, code == kVK_Delete || code == kVK_ForwardDelete {
                stop(saving: .some(nil))
            } else if let hotKey = HotKey(event: event) {
                stop(saving: hotKey)
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    /// Ends recording; `saving` is the new shortcut (`.some(nil)` turns it off), nil keeps the old one.
    private func stop(saving: HotKey?? = nil) {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let saving { shortcut.set(saving) } else { shortcut.resume() }
    }
}
#endif
