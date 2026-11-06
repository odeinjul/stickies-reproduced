import AppKit
import StickiesCore

protocol NoteWindowControllerDelegate: AnyObject {
    func noteDidChange(_ controller: NoteWindowController)
    func noteShouldBeDeleted(_ controller: NoteWindowController)
    func noteUseAsDefault(_ controller: NoteWindowController)
}

/// One note window: borderless, 12 pt spine on top, Markdown body below.
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    private(set) var note: Note
    weak var delegate: NoteWindowControllerDelegate?

    /// Draws the note as if focused; used by `--snapshot`.
    var forceActive = false { didSet { refreshChrome() } }

    let spine: SpineView
    let textView: NoteTextView
    private let scrollView: NSScrollView
    private let grow: GrowView
    private let edgeViews: [ResizeHandle]
    private var preZoomFrame: NSRect?
    private var isApplyingFrame = false
    /// The lines last rendered with their markers showing.
    private var editingLines: NSRange?
    /// Lines changed by typing since the last render, and the code fence count then.
    private var editedLines: NSRange?
    private var fenceCount = 0
    /// Shows these lines' markers regardless of focus; used by `--snapshot`.
    var editingOverride: NSRange? { didSet { render() } }

    init(note: Note) {
        self.note = note
        let size = note.frame.size
        let spineHeight = NoteLayout.spineHeight

        let window = NoteWindow(contentRect: note.frame,
                                styleMask: [.closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.minSize = NoteLayout.minSize
        // Measured from Stickies' nib: stationary + no full screen, no open animation, no tabs.
        window.collectionBehavior = [.stationary, .fullScreenNone]
        window.animationBehavior = .none
        window.tabbingMode = .disallowed
        // Notes are always light, so default text stays black in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)

        spine = SpineView(frame: NSRect(x: 0, y: size.height - spineHeight, width: size.width, height: spineHeight),
                          shades: note.color.shades)
        spine.autoresizingMask = [.width, .minYMargin]

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - spineHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // TextKit 1 with a layout manager that draws bullets, checkboxes, quotes and rules.
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: scrollView.contentSize.width,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = NoteTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: container)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 5, height: 4)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.usesFontPanel = true
        scrollView.documentView = textView

        let growSize = NoteLayout.growSize
        grow = GrowView(frame: NSRect(x: size.width - growSize, y: 0, width: growSize, height: growSize),
                        shades: note.color.shades)
        grow.autoresizingMask = [.minXMargin, .maxYMargin]

        let edge = NoteLayout.edgeThickness
        let top = NoteLayout.topEdgeThickness
        let left = ResizeHandle(frame: NSRect(x: 0, y: 0, width: edge, height: size.height), edges: .left)
        left.autoresizingMask = [.height, .maxXMargin]
        let right = ResizeHandle(frame: NSRect(x: size.width - edge, y: 0, width: edge, height: size.height),
                                   edges: .right)
        right.autoresizingMask = [.height, .minXMargin]
        let bottom = ResizeHandle(frame: NSRect(x: 0, y: 0, width: size.width, height: edge), edges: .bottom)
        bottom.autoresizingMask = [.width, .maxYMargin]
        let topEdge = ResizeHandle(frame: NSRect(x: 0, y: size.height - top, width: size.width, height: top),
                                     edges: .top)
        topEdge.autoresizingMask = [.width, .minYMargin]
        edgeViews = [left, right, bottom, topEdge]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(scrollView)
        content.addSubview(spine)
        edgeViews.forEach(content.addSubview)
        content.addSubview(grow)
        window.contentView = content

        super.init(window: window)
        window.delegate = self
        textView.delegate = self
        textView.textStorage?.delegate = self
        loadText()

        spine.closeButton.onPress = { [weak self] in self?.closeNote(nil) }
        spine.zoomButton.onPress = { [weak self] in self?.toggleZoom(nil) }
        spine.collapseButton.onPress = { [weak self] in self?.toggleCollapse(nil) }
        spine.onDoubleClick = { [weak self] in self?.toggleCollapse(nil) }
        textView.onStyleChange = { [weak self] in self?.captureTextStyle() }

        applyColor()
        applyWindowFlags()
        applyCollapse(animate: false)
        updateInfo()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Applying note state

    private func applyColor() {
        let shades = note.color.shades
        window?.backgroundColor = shades.body.nsColor
        textView.backgroundColor = shades.body.nsColor
        spine.shades = shades
        grow.shades = shades
        updateWindowsItem()
    }

    /// Title (first line) and colour swatch for the note list in the Window menu.
    private func updateWindowsItem() {
        guard let window else { return }
        let title = NoteTitle.of(note.text)
        window.title = title
        NSApp.changeWindowsItem(window, title: title, filename: false)
        NSApp.windowsMenu?.items.first { $0.target === window }?.image = MainMenu.swatch(note.color.shades)
    }

    private var defaultFont: NSFont {
        NSFont(name: note.fontName, size: note.fontSize) ?? .systemFont(ofSize: note.fontSize)
    }

    private func loadText() {
        textView.bodyFont = defaultFont
        textView.string = note.text
        fenceCount = MarkdownRenderer.fenceCount(in: note.text)
        render()
    }

    /// The lines whose markers show: the selection's, while the note is focused.
    private var editingRange: NSRange? {
        if let editingOverride { return editingOverride }
        guard window?.isKeyWindow == true else { return nil }
        return (textView.string as NSString).lineRange(for: textView.selectedRange())
    }

    /// Typora style: markers hidden except on the lines being edited. Restyles
    /// just `lines`, or the whole note when nil.
    private func render(lines: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        let style = note.markdownStyle
        editingLines = editingRange
        MarkdownRenderer.render(storage, style: style, editing: editingLines, lines: lines)
        editedLines = nil
        textView.typingAttributes = [.font: style.font, .foregroundColor: style.textColor]
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        editedLines = editedLines.map { NSUnionRange($0, editedRange) } ?? editedRange
    }

    private func applyWindowFlags() {
        window?.level = note.isFloating ? .floating : .normal
        window?.alphaValue = note.isTranslucent ? NoteLayout.translucentAlpha : 1
    }

    private func applyCollapse(animate: Bool) {
        guard let window else { return }
        let collapsed = note.isCollapsed
        scrollView.isHidden = collapsed
        spine.titleField.stringValue = NoteTitle.of(note.text)
        spine.titleField.isHidden = !collapsed
        if collapsed {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
        let target = collapsed
            ? NoteLayout.collapsedFrame(from: window.frame)
            : NoteLayout.expandedFrame(from: window.frame, height: note.frame.height)
        isApplyingFrame = true
        window.setFrame(target, display: true, animate: animate && window.isVisible)
        isApplyingFrame = false
        refreshChrome()
    }

    private func refreshChrome() {
        let active = forceActive || (window?.isKeyWindow ?? false)
        spine.isActive = active
        grow.isHidden = note.isCollapsed || !active
        edgeViews.forEach { $0.isHidden = note.isCollapsed }
    }

    private static let infoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Hovering over the bar shows when the note was created and last edited, as in Stickies.
    private func updateInfo() {
        let format = Self.infoFormatter
        spine.toolTip = "Created: \(format.string(from: note.created))\nModified: \(format.string(from: note.modified))"
    }

    // MARK: - Capturing changes

    private func captureFrame() {
        guard let window, !isApplyingFrame else { return }
        if note.isCollapsed {
            // Keep the expanded height; follow the bar's top edge.
            note.frame = NoteLayout.expandedFrame(from: window.frame, height: note.frame.height)
        } else {
            note.frame = window.frame
        }
        delegate?.noteDidChange(self)
    }

    /// The font panel, Bigger and Smaller set the whole note's font.
    private func captureTextStyle() {
        note.fontName = textView.bodyFont.fontName
        note.fontSize = Double(textView.bodyFont.pointSize)
        render()
        delegate?.noteDidChange(self)
    }

    func textDidChange(_ notification: Notification) {
        note.text = textView.string
        // Just the edited lines, unless a code fence opened or closed (that restyles what follows).
        let fences = MarkdownRenderer.fenceCount(in: note.text)
        render(lines: fences == fenceCount ? editedLines : nil)
        fenceCount = fences
        note.modified = Date()
        if note.isCollapsed { spine.titleField.stringValue = NoteTitle.of(note.text) }
        updateWindowsItem()
        updateInfo()
        delegate?.noteDidChange(self)
    }

    // MARK: - Find panel and Arrange By

    /// Shows a match: expands the note, brings it forward as the main window
    /// (the Find panel stays key) and selects the text.
    func reveal(_ range: NSRange) {
        if note.isCollapsed { toggleCollapse(nil) }
        window?.orderFront(nil)
        window?.makeMain()
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    func replace(_ range: NSRange, with string: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    /// Replaces every match in this note as one undoable change. Returns the count.
    func replaceAll(_ query: String, with string: String, ignoreCase: Bool) -> Int {
        let ranges = TextSearch.ranges(of: query, in: textView.string, ignoreCase: ignoreCase)
        guard !ranges.isEmpty,
              textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) },
                                        replacementStrings: Array(repeating: string, count: ranges.count))
        else { return 0 }
        textView.textStorage?.beginEditing()
        for range in ranges.reversed() { textView.textStorage?.replaceCharacters(in: range, with: string) }
        textView.textStorage?.endEditing()
        textView.didChangeText()
        return ranges.count
    }

    /// Where the window is and whether it is collapsed, for Undo/Redo Arrange.
    var placement: (frame: NSRect, isCollapsed: Bool) {
        (window?.frame ?? note.frame, note.isCollapsed)
    }

    func place(frame: NSRect, collapsed: Bool) {
        guard let window else { return }
        if collapsed != note.isCollapsed {
            note.isCollapsed = collapsed
            applyCollapse(animate: false)
        }
        window.setFrame(frame, display: true)
        delegate?.noteDidChange(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshChrome()
        render(lines: editingRange)
    }

    func windowDidResignKey(_ notification: Notification) {
        refreshChrome()
        if let editingLines { render(lines: editingLines) }
    }

    /// Moving to another line hides the markers of the line left and shows the new one's.
    func textViewDidChangeSelection(_ notification: Notification) {
        let previous = editingLines
        guard editingRange != previous else { return }
        for lines in [previous, editingRange].compactMap({ $0 }) { render(lines: lines) }
    }
    func windowDidMove(_ notification: Notification) { captureFrame() }
    func windowDidResize(_ notification: Notification) { captureFrame() }

    // MARK: - Actions

    /// Empty notes go away silently; others ask Save… / Cancel / Delete Note, like Stickies.
    @objc func closeNote(_ sender: Any?) {
        if note.isEmpty {
            delegate?.noteShouldBeDeleted(self)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to discard this note?"
        alert.informativeText = "If you don’t save this note, its contents will be lost."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Note")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if exportText() { delegate?.noteShouldBeDeleted(self) }
        case .alertThirdButtonReturn:
            delegate?.noteShouldBeDeleted(self)
        default:
            break
        }
    }

    @objc func exportNoteText(_ sender: Any?) {
        exportText()
    }

    private static let exportFormatKey = "ExportTextFormat"

    /// Save panel with Stickies' Format popup (RTFD, RTF, Plain Text) plus Markdown,
    /// which is the default.
    /// Remembers the last format. Returns true when written.
    @discardableResult
    private func exportText() -> Bool {
        let formats = TextFormat.allCases
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: formats.map(\.title))
        let last = UserDefaults.standard.string(forKey: Self.exportFormatKey).flatMap(TextFormat.init(rawValue:))
        popup.selectItem(at: formats.firstIndex(of: last ?? .markdown) ?? 0)
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Format:"), popup])
        accessory.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        accessory.setFrameSize(accessory.fittingSize)

        let panel = NSSavePanel()
        panel.accessoryView = accessory
        panel.nameFieldStringValue = NoteTitle.of(note.text)
        let format = { formats[popup.indexOfSelectedItem] }
        let updateType = ClosureTarget { panel.allowedContentTypes = [format().contentType] }
        popup.target = updateType
        popup.action = #selector(ClosureTarget.run)
        updateType.run()

        let response = withExtendedLifetime(updateType) { panel.runModal() }
        guard response == .OK, let url = panel.url else { return false }
        UserDefaults.standard.set(format().rawValue, forKey: Self.exportFormatKey)
        do {
            try TextFile.write(markdown: note.text, style: note.markdownStyle, as: format(), to: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Prints like Stickies: the note as it looks (markers gone) reflowed to the
    /// page on white, with AppKit's header (title and date) and footer (page number).
    @objc func printNote(_ sender: Any?) {
        makePrintOperation(printInfo: NSPrintInfo.shared).run()
    }

    func makePrintOperation(printInfo base: NSPrintInfo) -> NSPrintOperation {
        let info = base.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter.rawValue] = true

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let page = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        page.drawsBackground = false
        page.isVerticallyResizable = true
        page.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        page.textStorage?.setAttributedString(MarkdownRenderer.rendered(note.text, style: note.markdownStyle))
        page.sizeToFit()

        let operation = NSPrintOperation(view: page, printInfo: info)
        operation.jobTitle = "Stickies MD"
        return operation
    }

    @objc func toggleFloating(_ sender: Any?) {
        note.isFloating.toggle()
        applyWindowFlags()
        delegate?.noteDidChange(self)
    }

    @objc func toggleTranslucent(_ sender: Any?) {
        note.isTranslucent.toggle()
        applyWindowFlags()
        delegate?.noteDidChange(self)
    }

    @objc func toggleCollapse(_ sender: Any?) {
        note.isCollapsed.toggle()
        applyCollapse(animate: true)
        delegate?.noteDidChange(self)
    }

    /// Like Stickies: fills the screen's visible area (not full screen mode);
    /// zooming again restores the earlier frame. Collapsing a zoomed note leaves
    /// a full-width bar along the top of the screen.
    @objc func toggleZoom(_ sender: Any?) {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        if note.isCollapsed { toggleCollapse(nil) }
        if let saved = preZoomFrame {
            preZoomFrame = nil
            window.setFrame(saved, display: true, animate: true)
        } else {
            preZoomFrame = window.frame
            window.setFrame(visible, display: true, animate: true)
        }
    }

    @objc func setPresetColor(_ sender: NSMenuItem) {
        guard NotePreset.allCases.indices.contains(sender.tag) else { return }
        note.color = .preset(NotePreset.allCases[sender.tag])
        applyColor()
        delegate?.noteDidChange(self)
    }

    func setColor(_ color: NoteColor) {
        note.color = color
        applyColor()
        delegate?.noteDidChange(self)
    }

    /// Opens the colour panel beside this note; every pick is passed to `onChange`.
    func editColor(from color: RGB, onChange: @escaping (RGB) -> Void) {
        textView.noteColorHandler = { onChange(RGB($0)) }
        NSColorPanel.shared.color = color.nsColor
        showPanel(NSColorPanel.shared)
    }

    /// Font → Show Fonts, with the panel showing this note's font.
    @objc func showFonts(_ sender: Any?) {
        guard let panel = NSFontManager.shared.fontPanel(true) else { return }
        NSFontManager.shared.setSelectedFont(textView.bodyFont, isMultiple: false)
        showPanel(panel)
    }

    /// Opens a Fonts or Colors panel right beside this note.
    private func showPanel(_ panel: NSPanel) {
        if let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrame(NoteLayout.panelFrame(size: panel.frame.size, beside: window.frame, in: visible),
                           display: false)
        }
        panel.orderFront(nil)
    }

    @objc func useAsDefault(_ sender: Any?) {
        delegate?.noteUseAsDefault(self)
    }
}

/// Target for a control whose action is a closure.
private final class ClosureTarget: NSObject {
    let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    @objc func run() { body() }
}

extension NoteWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleFloating(_:)):
            item.state = note.isFloating ? .on : .off
        case #selector(toggleTranslucent(_:)):
            item.state = note.isTranslucent ? .on : .off
        case #selector(toggleCollapse(_:)):
            item.title = note.isCollapsed ? "Expand" : "Collapse"
        case #selector(setPresetColor(_:)):
            let preset = NotePreset.allCases.indices.contains(item.tag) ? NotePreset.allCases[item.tag] : nil
            item.state = preset.map { note.color == .preset($0) } == true ? .on : .off
        default:
            break
        }
        return true
    }
}
