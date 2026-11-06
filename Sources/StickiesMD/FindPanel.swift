import AppKit
import StickiesCore

/// Stickies' Find panel: find and replace in the current note or in all notes.
final class FindPanelController: NSWindowController {
    private let notes: () -> [NoteWindowController]

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let currentNoteButton = NSButton(radioButtonWithTitle: "Current Note", target: nil, action: nil)
    private let allNotesButton = NSButton(radioButtonWithTitle: "All Notes", target: nil, action: nil)
    private let ignoreCaseButton = NSButton(checkboxWithTitle: "Ignore Case", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")

    init(notes: @escaping () -> [NoteWindowController]) {
        self.notes = notes
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = "Find"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        super.init(window: panel)
        buildContent(in: panel)
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(in panel: NSPanel) {
        // Radio buttons sharing an action and superview act as one group.
        for radio in [currentNoteButton, allNotesButton] {
            radio.target = self
            radio.action = #selector(scopeChanged(_:))
        }
        currentNoteButton.state = .on
        ignoreCaseButton.state = .on
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Find:"), findField],
            [NSTextField(labelWithString: "Replace With:"), replaceField],
            [NSTextField(labelWithString: "Options:"),
             NSStackView(views: [currentNoteButton, allNotesButton, ignoreCaseButton])],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8

        let buttons = [
            NSButton(title: "Replace All", target: self, action: #selector(replaceAll(_:))),
            NSButton(title: "Replace", target: self, action: #selector(replace(_:))),
            NSButton(title: "Replace & Find", target: self, action: #selector(replaceAndFind(_:))),
            NSButton(title: "Previous", target: self, action: #selector(findPrevious(_:))),
            NSButton(title: "Next", target: self, action: #selector(findNext(_:))),
        ]
        buttons.last?.keyEquivalent = "\r"
        status.textColor = .secondaryLabelColor
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [status] + buttons)

        let stack = NSStackView(views: [grid, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        buttonRow.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(findField)
        findField.selectText(nil)
    }

    /// The focused note, or the last main note while this panel is key.
    private var target: NoteWindowController? {
        let all = notes()
        for window in [NSApp.keyWindow, NSApp.mainWindow] {
            if let note = all.first(where: { $0.window === window }) { return note }
        }
        return all.first
    }

    private var ignoreCase: Bool { ignoreCaseButton.state == .on }
    private var searchesAllNotes: Bool { allNotesButton.state == .on }

    @objc private func scopeChanged(_ sender: NSButton) {}

    @objc func findNext(_ sender: Any?) { find(forward: true) }
    @objc func findPrevious(_ sender: Any?) { find(forward: false) }

    @discardableResult
    private func find(forward: Bool) -> Bool {
        let query = findField.stringValue
        guard !query.isEmpty, let start = target else {
            NSSound.beep()
            return false
        }
        let selection = start.textView.selectedRange()
        let location = forward ? NSMaxRange(selection) : selection.location
        let found: (note: NoteWindowController, range: NSRange)?
        if searchesAllNotes {
            let all = notes()
            let index = all.firstIndex { $0 === start } ?? 0
            found = TextSearch.match(of: query, in: all.map(\.textView.string), note: index, from: location,
                                     forward: forward, ignoreCase: ignoreCase)
                .map { (all[$0.note], $0.range) }
        } else {
            found = TextSearch.match(of: query, in: start.textView.string, from: location, forward: forward,
                                     ignoreCase: ignoreCase, wraps: true)
                .map { (start, $0) }
        }
        guard let found else {
            status.stringValue = "Not found"
            NSSound.beep()
            return false
        }
        status.stringValue = ""
        found.note.reveal(found.range)
        return true
    }

    /// Replaces the selection when it is the current match.
    @objc func replace(_ sender: Any?) {
        guard let note = target else { return }
        let range = note.textView.selectedRange()
        let selected = (note.textView.string as NSString).substring(with: range)
        guard range.length > 0,
              selected.compare(findField.stringValue, options: TextSearch.options(ignoreCase: ignoreCase)) == .orderedSame
        else {
            NSSound.beep()
            return
        }
        note.replace(range, with: replaceField.stringValue)
        status.stringValue = ""
    }

    @objc func replaceAndFind(_ sender: Any?) {
        replace(sender)
        find(forward: true)
    }

    @objc func replaceAll(_ sender: Any?) {
        let scope = searchesAllNotes ? notes() : (target.map { [$0] } ?? [])
        let count = scope.reduce(0) {
            $0 + $1.replaceAll(findField.stringValue, with: replaceField.stringValue, ignoreCase: ignoreCase)
        }
        status.stringValue = count == 0 ? "Not found" : "\(count) replaced"
        if count == 0 { NSSound.beep() }
    }

    /// Edit → Find → Use Selection for Find.
    func useSelectionForFind() {
        guard let note = target, note.textView.selectedRange().length > 0 else {
            NSSound.beep()
            return
        }
        findField.stringValue = (note.textView.string as NSString).substring(with: note.textView.selectedRange())
    }

    /// Edit → Find → Jump to Selection.
    func jumpToSelection() {
        guard let note = target else { return }
        note.window?.makeKeyAndOrderFront(nil)
        note.textView.scrollRangeToVisible(note.textView.selectedRange())
    }
}
