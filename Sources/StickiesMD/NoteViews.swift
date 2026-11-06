import AppKit
import StickiesCore

/// Untitled windows refuse key status by default; notes need it for typing.
final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One of the three 8×8 pt bar buttons, drawn like Stickies' glyphs.
final class SpineButton: NSView {
    enum Kind { case close, zoom, collapse }

    let kind: Kind
    var shades: NoteShades { didSet { needsDisplay = true } }
    var onPress: () -> Void = {}
    private(set) var isPressed = false { didSet { needsDisplay = true } }

    init(kind: Kind, frame: NSRect, shades: NoteShades) {
        self.kind = kind
        self.shades = shades
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        switch kind {
        case .close: setAccessibilityLabel("Close")
        case .zoom: setAccessibilityLabel("Zoom")
        case .collapse: setAccessibilityLabel("Collapse")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path: NSBezierPath
        switch kind {
        case .close, .collapse:
            path = NSBezierPath(rect: box)
        case .zoom:
            // Lower-right half: ◢
            path = NSBezierPath()
            path.move(to: NSPoint(x: box.minX, y: box.minY))
            path.line(to: NSPoint(x: box.maxX, y: box.minY))
            path.line(to: NSPoint(x: box.maxX, y: box.maxY))
            path.close()
        }
        (isPressed ? shades.highlight : shades.body).nsColor.setFill()
        path.fill()
        if kind == .collapse {
            shades.collapseBar.nsColor.setFill()
            NSRect(x: 1, y: 4, width: bounds.width - 2, height: 2).fill()
        }
        shades.control.nsColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { onPress() }
    }
}

/// The 12 pt bar on top of a note: drag to move, double-click to collapse.
final class SpineView: NSView {
    let closeButton: SpineButton
    let zoomButton: SpineButton
    let collapseButton: SpineButton
    let titleField = NSTextField(labelWithString: "")
    var onDoubleClick: () -> Void = {}

    var shades: NoteShades {
        didSet {
            needsDisplay = true
            buttons.forEach { $0.shades = shades }
        }
    }

    /// Only the focused note shows the spine colour and buttons.
    var isActive = false {
        didSet {
            needsDisplay = true
            buttons.forEach { $0.isHidden = !isActive }
        }
    }

    private var buttons: [SpineButton] { [closeButton, zoomButton, collapseButton] }

    init(frame: NSRect, shades: NoteShades) {
        let width = frame.width
        self.shades = shades
        closeButton = SpineButton(kind: .close, frame: NoteLayout.closeFrame(width: width), shades: shades)
        zoomButton = SpineButton(kind: .zoom, frame: NoteLayout.zoomFrame(width: width), shades: shades)
        collapseButton = SpineButton(kind: .collapse, frame: NoteLayout.collapseFrame(width: width), shades: shades)
        super.init(frame: frame)

        closeButton.autoresizingMask = [.maxXMargin]
        zoomButton.autoresizingMask = [.minXMargin]
        collapseButton.autoresizingMask = [.minXMargin]

        titleField.frame = NoteLayout.titleFrame(width: width)
        titleField.autoresizingMask = [.width]
        titleField.font = .systemFont(ofSize: 9)
        titleField.textColor = .black
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isHidden = true

        addSubview(titleField)
        buttons.forEach { addSubview($0); $0.isHidden = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        (isActive ? shades.spine : shades.body).nsColor.setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// Dragging resizes the note from `edges`. Along a single edge, a drag near either
/// end also moves the neighbouring edge, so the strips work as corners too.
class ResizeHandle: NSView {
    let edges: ResizeEdges
    private var dragging: ResizeEdges = []
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    init(frame: NSRect, edges: ResizeEdges) {
        self.edges = edges
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if edges == .left || edges == .right { addCursorRect(bounds, cursor: .resizeLeftRight) }
        if edges == .top || edges == .bottom { addCursorRect(bounds, cursor: .resizeUpDown) }
    }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
        let point = convert(event.locationInWindow, from: nil)
        let corner = NoteLayout.cornerSize
        dragging = edges
        if edges == .left || edges == .right {
            if point.y < corner { dragging.insert(.bottom) }
            if point.y > bounds.height - corner { dragging.insert(.top) }
        } else if edges == .top || edges == .bottom {
            if point.x < corner { dragging.insert(.left) }
            if point.x > bounds.width - corner { dragging.insert(.right) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        window?.setFrame(NoteLayout.resized(startFrame, edges: dragging,
                                            dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y),
                         display: true)
    }
}

/// The bottom-right grip, with the clone's three-line resize sign.
final class GrowView: ResizeHandle {
    var shades: NoteShades { didSet { needsDisplay = true } }

    init(frame: NSRect, shades: NoteShades) {
        self.shades = shades
        super.init(frame: frame, edges: [.right, .bottom])
        setAccessibilityElement(true)
        setAccessibilityLabel("grow area")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let width = superview?.bounds.width ?? frame.maxX
        let path = NSBezierPath()
        for line in NoteLayout.resizeLines(width: width) {
            path.move(to: NSPoint(x: line.start.x - frame.minX, y: line.start.y - frame.minY))
            path.line(to: NSPoint(x: line.end.x - frame.minX, y: line.end.y - frame.minY))
        }
        path.lineWidth = 1
        shades.control.nsColor.setStroke()
        path.stroke()
    }
}

/// The note's editor. The text is Markdown, styled in place by the controller;
/// the font and size apply to the whole note.
final class NoteTextView: NSTextView {
    var onStyleChange: () -> Void = {}
    /// When set, the colour panel recolours the note instead of the text.
    var noteColorHandler: ((NSColor) -> Void)?
    var bodyFont = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)

    /// Font panel, Bigger and Smaller: the whole note's font.
    override func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        bodyFont = manager.convert(bodyFont)
        onStyleChange()
    }

    /// The colour panel only recolours the note (Color → Customize Color…);
    /// Markdown has no text colours.
    override func changeColor(_ sender: Any?) {
        guard let panel = sender as? NSColorPanel else { return }
        noteColorHandler?(panel.color)
    }

    /// Typing, pasting and every other edit stop at `NoteLimits.maxCharacters`.
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        if let replacementString, !fits(replacing: [range], with: [replacementString]) { return false }
        return super.shouldChangeText(in: range, replacementString: replacementString)
    }

    override func shouldChangeText(inRanges ranges: [NSValue], replacementStrings: [String]?) -> Bool {
        if let replacementStrings, !fits(replacing: ranges.map(\.rangeValue), with: replacementStrings) { return false }
        return super.shouldChangeText(inRanges: ranges, replacementStrings: replacementStrings)
    }

    private func fits(replacing ranges: [NSRange], with strings: [String]) -> Bool {
        let removed = ranges.reduce(0) { $0 + $1.length }
        let added = strings.reduce(0) { $0 + ($1 as NSString).length }
        let current = (string as NSString).length
        guard NoteLimits.allows(replacing: NSRange(location: 0, length: removed), with: added, in: current) else {
            NSSound.beep()
            if added > 1 {
                let alert = NSAlert()
                alert.messageText = "This note is full."
                alert.informativeText = "A note can hold up to \(NoteLimits.maxCharacters.formatted()) characters. "
                    + "Make room or start a new note."
                alert.runModal()
            }
            return false
        }
        return true
    }

    // Font menu: Markdown markers around the selection.
    @objc func markdownBold(_ sender: Any?) { MarkdownEditing.toggleWrap("**", "**", in: self) }
    @objc func markdownItalic(_ sender: Any?) { MarkdownEditing.toggleWrap("*", "*", in: self) }
    @objc func markdownUnderline(_ sender: Any?) { MarkdownEditing.toggleWrap("<u>", "</u>", in: self) }
    @objc func markdownStrikethrough(_ sender: Any?) { MarkdownEditing.toggleWrap("~~", "~~", in: self) }

    override func insertNewline(_ sender: Any?) {
        if !MarkdownEditing.handleNewline(in: self) { super.insertNewline(sender) }
    }

    override func insertTab(_ sender: Any?) {
        if !MarkdownEditing.indent(in: self, outdent: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !MarkdownEditing.indent(in: self, outdent: true) { super.insertBacktab(sender) }
    }

    /// Option-Tab starts a list, as in Stickies; inside a list it types a tab.
    override func insertTabIgnoringFieldEditor(_ sender: Any?) {
        if !MarkdownEditing.startList(in: self) { super.insertTabIgnoringFieldEditor(sender) }
    }

    /// A click on a drawn checkbox (in the gutter before the item) ticks it.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let line = checkboxLine(at: point), MarkdownEditing.toggleTask(atLine: line, in: self) { return }
        super.mouseDown(with: event)
    }

    private func checkboxLine(at point: NSPoint) -> Int? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = min(characterIndexForInsertion(at: point), storage.length - 1)
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var isCheckbox = false
        storage.enumerateAttribute(.markdownDecoration, in: line) { value, _, stop in
            if let raw = value as? String, [MarkdownDecoration.unchecked, .checked].contains(MarkdownDecoration(rawValue: raw)) {
                isCheckbox = true
                stop.pointee = true
            }
        }
        let paragraph = storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle
        let gutter = textContainerOrigin.x + (paragraph?.headIndent ?? 0)
        return isCheckbox && point.x < gutter ? line.location : nil
    }
}
