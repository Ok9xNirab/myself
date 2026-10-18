import SwiftUI

/// Keys a note block's editor reports instead of handling itself.
enum NoteKey {
    case `return`, backspace, up, down, escape, tab, commandReturn
}

/// What the editor sees when a key arrives: the selection (UTF-16) and text length.
struct NoteKeyContext {
    var selection: NSRange
    var length: Int
    var atStart: Bool { selection.location == 0 && selection.length == 0 }
    var atEnd: Bool { selection.length == 0 && selection.location == length }
}

/// Asks a block's text view to take focus with the caret at `caret` (`nil` = end). A new `token` repeats the request.
struct NoteFocusRequest: Equatable {
    var caret: Int?
    var token = UUID()
}

/// The text view currently being edited, so the toolbar can format its selection.
final class NoteTextFocus {
    #if os(macOS)
    weak var textView: NoteNSTextView?
    #endif

    /// Wraps the selection in markdown markers, or unwraps it if they're already there.
    func wrap(_ before: String, _ after: String, placeholder: String = "text") {
        #if os(macOS)
        textView?.wrap(before, after, placeholder: placeholder)
        #endif
    }

    var selectionStart: Int? {
        #if os(macOS)
        textView?.selectedRange().location
        #else
        nil
        #endif
    }
}

#if os(macOS)
import AppKit

/// A self-sizing plain-text editor for one note block (or the title, or a code/LaTeX block).
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var lineSpacing: CGFloat = 0
    var textColor: NSColor = .labelColor
    var placeholder = ""
    /// Highlights the text as code in this language.
    var code: CodeLanguage?
    /// ⌘B, ⌘I, ⌘E, ⌘K, ⇧⌘X, ⇧⌘M, ⇧⌘H wrap the selection in markdown.
    var formatting = false
    var focus: NoteFocusRequest?
    var focusTracker: NoteTextFocus?
    var onKey: (NoteKey, NoteKeyContext) -> Bool = { _, _ in false }
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NoteNSTextView {
        let view = NoteNSTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 3)
        view.textContainer?.lineFragmentPadding = 2
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.string = text
        return view
    }

    func updateNSView(_ view: NoteNSTextView, context: Context) {
        context.coordinator.parent = self
        view.parent = self
        view.focusTracker = focusTracker
        view.placeholder = placeholder
        view.formatting = formatting
        if view.string != text {
            view.string = text
            context.coordinator.highlight(view)
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        if view.font != font || view.defaultParagraphStyle != style || view.textColor != textColor {
            view.font = font
            view.textColor = textColor
            view.defaultParagraphStyle = style
            view.typingAttributes = [.font: font, .foregroundColor: textColor, .paragraphStyle: style]
            if let storage = view.textStorage {
                storage.setAttributes(view.typingAttributes, range: NSRange(location: 0, length: storage.length))
            }
            context.coordinator.highlight(view)
        }
        if let focus, focus != context.coordinator.appliedFocus {
            context.coordinator.appliedFocus = focus
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                window.makeFirstResponder(view)
                let length = (view.string as NSString).length
                view.setSelectedRange(NSRange(location: min(focus.caret ?? length, length), length: 0))
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NoteNSTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? 400
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        // The extra line fragment is the empty line after a trailing newline (or of an empty block).
        let height = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: ceil(height + view.textContainerInset.height * 2))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView?
        var appliedFocus: NoteFocusRequest?

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NoteNSTextView, let parent else { return }
            highlight(view)
            if parent.text != view.string { parent.text = view.string }
            view.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let parent else { return false }
            let context = NoteKeyContext(selection: textView.selectedRange(), length: (textView.string as NSString).length)
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            let command = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            let key: NoteKey? = switch selector {
            case #selector(NSResponder.insertNewline(_:)): command ? .commandReturn : shift ? nil : .return
            case #selector(NSResponder.deleteBackward(_:)): .backspace
            case #selector(NSResponder.moveUp(_:)): .up
            case #selector(NSResponder.moveDown(_:)): .down
            case #selector(NSResponder.cancelOperation(_:)): .escape
            case #selector(NSResponder.insertTab(_:)): .tab
            default: nil
            }
            guard let key else { return false }
            return parent.onKey(key, context)
        }

        /// Colours code by token with temporary attributes, which leave the plain text untouched.
        func highlight(_ view: NSTextView) {
            guard let lang = parent?.code, let layout = view.layoutManager else { return }
            let full = NSRange(location: 0, length: (view.string as NSString).length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            for (range, token) in CodeHighlighter.tokens(view.string, lang) {
                layout.addTemporaryAttribute(.foregroundColor, value: NoteColors.token(token), forCharacterRange: range)
            }
        }
    }
}

final class NoteNSTextView: NSTextView {
    var parent: NoteTextView?
    weak var focusTracker: NoteTextFocus?
    var placeholder = ""
    var formatting = false

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            focusTracker?.textView = self
            parent?.onFocusChange(true)
            needsDisplay = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            if focusTracker?.textView === self { focusTracker?.textView = nil }
            parent?.onFocusChange(false)
            needsDisplay = true
        }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard formatting, window?.firstResponder === self, event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        let markers: (String, String, String)? = switch (shift, key) {
        case (false, "b"): ("**", "**", "text")
        case (false, "i"): ("*", "*", "text")
        case (false, "e"): ("`", "`", "code")
        case (false, "k"): ("[", "](https://)", "link")
        case (true, "x"): ("~~", "~~", "text")
        case (true, "m"): ("$", "$", "x^2")
        case (true, "h"): ("==", "==", "text")
        default: nil
        }
        guard let markers else { return super.performKeyEquivalent(with: event) }
        wrap(markers.0, markers.1, placeholder: markers.2)
        return true
    }

    func wrap(_ before: String, _ after: String, placeholder: String) {
        let ns = string as NSString
        let r = selectedRange()
        let b = (before as NSString).length, a = (after as NSString).length
        if r.location >= b, NSMaxRange(r) + a <= ns.length,
           ns.substring(with: NSRange(location: r.location - b, length: b)) == before,
           ns.substring(with: NSRange(location: NSMaxRange(r), length: a)) == after {
            let inner = ns.substring(with: r)
            let outer = NSRange(location: r.location - b, length: r.length + b + a)
            insertText(inner, replacementRange: outer)
            setSelectedRange(NSRange(location: outer.location, length: r.length))
            return
        }
        let inner = r.length > 0 ? ns.substring(with: r) : placeholder
        insertText(before + inner + after, replacementRange: r)
        setSelectedRange(NSRange(location: r.location + b, length: (inner as NSString).length))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor])
    }
}

#else

/// iOS and iPadOS: a plain vertical text field. Return splits the block at the end; the other keys aren't reported.
struct NoteTextView: View {
    @Binding var text: String
    var font: UIFont
    var lineSpacing: CGFloat = 0
    var textColor: UIColor = .label
    var placeholder = ""
    var code: CodeLanguage?
    var formatting = false
    var focus: NoteFocusRequest?
    var focusTracker: NoteTextFocus?
    var onKey: (NoteKey, NoteKeyContext) -> Bool = { _, _ in false }
    var onFocusChange: (Bool) -> Void = { _ in }
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(Font(font))
            .lineSpacing(lineSpacing)
            .foregroundStyle(Color(textColor))
            .focused($focused)
            .onSubmit {
                let length = (text as NSString).length
                _ = onKey(.return, NoteKeyContext(selection: NSRange(location: length, length: 0), length: length))
            }
            .onChange(of: focus) { if focus != nil { focused = true } }
            .onChange(of: focused) { onFocusChange(focused) }
            .onAppear { if focus != nil { focused = true } }
    }
}

#endif
