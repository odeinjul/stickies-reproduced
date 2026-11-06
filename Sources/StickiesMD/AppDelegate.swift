import AppKit
import StickiesCore

final class AppDelegate: NSObject, NSApplicationDelegate, NoteWindowControllerDelegate {
    private let store: NoteStore
    private var defaults = NoteDefaults()
    private var controllers: [NoteWindowController] = []
    private var pendingSave: DispatchWorkItem?
    /// Off when loading failed, so a broken index is never overwritten.
    private var canSave = true
    private lazy var finder = FindPanelController { [unowned self] in self.controllers }
    /// Window → Undo/Redo Arrange: where each note was, by note id.
    private var arrangeUndo: [UUID: (frame: NSRect, isCollapsed: Bool)]?
    private var arrangeRedo: [UUID: (frame: NSRect, isCollapsed: Bool)]?

    init(store: NoteStore = .standard()) {
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        do {
            let loaded = try store.load()
            defaults = loaded.defaults
            loaded.notes.forEach(show)
        } catch {
            canSave = false
            NSAlert(error: error).runModal()
        }
        if controllers.isEmpty { addNote(text: "") }
        // Writes notes converted from older .rtf/.txt files out as .md right away.
        scheduleSave()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringAllToFront(nil)
        return true
    }

    // MARK: - Notes

    private func show(_ note: Note) {
        let controller = NoteWindowController(note: note)
        controller.delegate = self
        controllers.append(controller)
        controller.showWindow(nil)
    }

    /// New notes cascade from the focused note, else start near the top-left of the screen.
    private func addNote(text: String) {
        var frame = CGRect(origin: .zero, size: defaults.size)
        if let key = NSApp.keyWindow, controllers.contains(where: { $0.window === key }) {
            frame.origin = CGPoint(x: key.frame.minX + 20, y: key.frame.maxY - 20 - frame.height)
        } else if let visible = NSScreen.main?.visibleFrame {
            frame.origin = CGPoint(x: visible.minX + 40, y: visible.maxY - 40 - frame.height)
        }
        show(Note(defaults: defaults, frame: frame, text: text))
        scheduleSave()
    }

    @objc func newNote(_ sender: Any?) {
        addNote(text: "")
    }

    /// Each file becomes a new note. RTF and RTFD formatting turns into Markdown; pictures are dropped.
    @objc func importText(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = TextFormat.allCases.map(\.contentType)
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let (text, wasCut) = NoteLimits.fitted(try TextFile.readMarkdown(url))
                addNote(text: text)
                if wasCut {
                    let alert = NSAlert()
                    alert.messageText = "“\(url.lastPathComponent)” was shortened."
                    alert.informativeText = "A note can hold up to \(NoteLimits.maxCharacters.formatted()) characters; "
                        + "the rest of the file wasn’t imported."
                    alert.runModal()
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Writes notes into colour folders and hands the folder to Notes, as Stickies does.
    @objc func exportAllToNotes(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Export all notes to Notes?"
        alert.informativeText = "Your notes will appear in an “Imported Notes” folder in the Notes application. "
            + "Text formatting and links will be preserved. "
            + "Notes will be organized into separate folders based on color."
        alert.addButton(withTitle: "Export All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("Stickies MD", isDirectory: true)
            try NotesExport.write(controllers.map(\.note), to: root)
            let notesApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes")
                ?? URL(fileURLWithPath: "/System/Applications/Notes.app")
            NSWorkspace.shared.open([root], withApplicationAt: notesApp,
                                    configuration: NSWorkspace.OpenConfiguration())
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// About Stickies MD: the version, what it recreates, and who made it.
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits])
        NSApp.activate(ignoringOtherApps: true)
    }

    static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: """
            A recreation of Stickies Version 10.3 (10.3)
            Copyright © 1999–2024 Apple Inc. All rights reserved.
            Not affiliated with or endorsed by Apple.

            Made by Claude Opus 5.5 and @odeinjul
            """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                              .paragraphStyle: paragraph])
    }

    @objc func bringAllToFront(_ sender: Any?) {
        controllers.forEach { $0.window?.orderFront(nil) }
    }

    // MARK: - Find

    @objc func showFindPanel(_ sender: Any?) { finder.show() }
    @objc func findNext(_ sender: Any?) { finder.findNext(sender) }
    @objc func findPrevious(_ sender: Any?) { finder.findPrevious(sender) }
    @objc func useSelectionForFind(_ sender: Any?) { finder.useSelectionForFind() }
    @objc func jumpToSelection(_ sender: Any?) { finder.jumpToSelection() }


    // MARK: - Arrange By

    /// Collapses every note and stacks the bars at the top-left of the main screen, sorted.
    @objc func arrangeNotes(_ sender: NSMenuItem) {
        guard let order = ArrangeOrder(rawValue: sender.tag),
              let visible = NSScreen.screens.first?.visibleFrame else { return }
        let before = placements()
        let sorted = NoteArrange.sorted(controllers.map(\.note), by: order).compactMap { note in
            controllers.first { $0.note.id == note.id }
        }
        let frames = NoteLayout.arrangedFrames(widths: sorted.map { $0.window?.frame.width ?? 300 }, in: visible)
        for (controller, frame) in zip(sorted, frames) {
            controller.place(frame: frame, collapsed: true)
        }
        arrangeUndo = before
        arrangeRedo = nil
    }

    @objc func undoArrange(_ sender: Any?) {
        guard let undo = arrangeUndo else { return }
        arrangeRedo = placements()
        restore(undo)
        arrangeUndo = nil
    }

    @objc func redoArrange(_ sender: Any?) {
        guard let redo = arrangeRedo else { return }
        arrangeUndo = placements()
        restore(redo)
        arrangeRedo = nil
    }

    private func placements() -> [UUID: (frame: NSRect, isCollapsed: Bool)] {
        Dictionary(uniqueKeysWithValues: controllers.map { ($0.note.id, $0.placement) })
    }

    private func restore(_ placements: [UUID: (frame: NSRect, isCollapsed: Bool)]) {
        for controller in controllers {
            guard let placement = placements[controller.note.id] else { continue }
            controller.place(frame: placement.frame, collapsed: placement.isCollapsed)
        }
    }

    // MARK: - NoteWindowControllerDelegate

    func noteDidChange(_ controller: NoteWindowController) {
        scheduleSave()
    }

    func noteShouldBeDeleted(_ controller: NoteWindowController) {
        controllers.removeAll { $0 === controller }
        if let window = controller.window { NSApp.removeWindowsItem(window) }
        controller.close()
        saveNow()
    }

    func noteUseAsDefault(_ controller: NoteWindowController) {
        let note = controller.note
        defaults.color = note.color
        defaults.fontName = note.fontName
        defaults.fontSize = note.fontSize
        defaults.isFloating = note.isFloating
        defaults.isTranslucent = note.isTranslucent
        defaults.size = note.frame.size
        scheduleSave()
    }

    // MARK: - Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canSave else { return }
        do {
            try store.save(notes: controllers.map(\.note), defaults: defaults)
        } catch {
            NSLog("Stickies MD: save failed: \(error)")
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undoArrange(_:)): return arrangeUndo != nil
        case #selector(redoArrange(_:)): return arrangeRedo != nil
        case #selector(arrangeNotes(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)),
             #selector(useSelectionForFind(_:)), #selector(jumpToSelection(_:)):
            return !controllers.isEmpty
        default: return true
        }
    }
}
