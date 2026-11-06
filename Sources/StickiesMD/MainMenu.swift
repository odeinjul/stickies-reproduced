import AppKit
import StickiesCore

/// Menus mirror Stickies: File, Edit, Font, Color, Window.
enum MainMenu {
    static func build() -> NSMenu {
        let fonts = NSFontManager.shared
        let main = NSMenu()

        main.addItem(submenu("Stickies MD", [
            item("About Stickies MD", #selector(AppDelegate.showAbout(_:))),
            .separator(),
            item("Hide Stickies MD", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Stickies MD", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New Note", #selector(AppDelegate.newNote(_:)), "n"),
            .separator(),
            item("Close", #selector(NoteWindowController.closeNote(_:)), "w"),
            .separator(),
            item("Import Text…", #selector(AppDelegate.importText(_:))),
            item("Export Text…", #selector(NoteWindowController.exportNoteText(_:))),
            .separator(),
            item("Export All to Notes…", #selector(AppDelegate.exportAllToNotes(_:))),
            .separator(),
            item("Print…", #selector(NoteWindowController.printNote(_:)), "p"),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            // Stickies' own Find panel, searching the current note or all notes.
            submenu("Find", [
                item("Find…", #selector(AppDelegate.showFindPanel(_:)), "f"),
                item("Find Next", #selector(AppDelegate.findNext(_:)), "g"),
                item("Find Previous", #selector(AppDelegate.findPrevious(_:)), "g", [.command, .shift]),
                item("Use Selection for Find", #selector(AppDelegate.useSelectionForFind(_:)), "e"),
                item("Jump to Selection", #selector(AppDelegate.jumpToSelection(_:)), "j"),
            ]),
        ]))

        // Markdown notes: Bold, Italic, Underline and Strikethrough add markers;
        // the font and size apply to the whole note. No text colours (Markdown has none).
        main.addItem(submenu("Font", [
            item("Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t", target: fonts),
            item("Bold", #selector(NoteTextView.markdownBold(_:)), "b"),
            item("Italic", #selector(NoteTextView.markdownItalic(_:)), "i"),
            item("Underline", #selector(NoteTextView.markdownUnderline(_:)), "u"),
            item("Strikethrough", #selector(NoteTextView.markdownStrikethrough(_:))),
            .separator(),
            item("Bigger", #selector(NSFontManager.modifyFont(_:)), "+", target: fonts,
                 tag: Int(NSFontAction.sizeUpFontAction.rawValue)),
            item("Smaller", #selector(NSFontManager.modifyFont(_:)), "-", target: fonts,
                 tag: Int(NSFontAction.sizeDownFontAction.rawValue)),
        ]))

        // Swatch, checkmark on the current colour, ⌘1–⌘6, as in Stickies.
        var colors = NotePreset.allCases.enumerated().map { index, preset -> NSMenuItem in
            let colorItem = item(preset.title, #selector(NoteWindowController.setPresetColor(_:)), "\(index + 1)",
                                 tag: index)
            colorItem.image = swatch(preset.shades)
            return colorItem
        }
        colors += [.separator(), item("Customize Color…", #selector(NoteWindowController.customizeColor(_:)))]
        main.addItem(submenu("Color", colors))

        let window = submenu("Window", [
            item("Collapse", #selector(NoteWindowController.toggleCollapse(_:)), "m"),
            item("Zoom", #selector(NoteWindowController.toggleZoom(_:)), "m", [.command, .shift]),
            .separator(),
            item("Float on Top", #selector(NoteWindowController.toggleFloating(_:)), "f", [.command, .option]),
            item("Translucent", #selector(NoteWindowController.toggleTranslucent(_:)), "t", [.command, .option]),
            item("Use as Default", #selector(NoteWindowController.useAsDefault(_:))),
            .separator(),
            item("Undo Arrange", #selector(AppDelegate.undoArrange(_:)), "z", [.command, .option]),
            item("Redo Arrange", #selector(AppDelegate.redoArrange(_:)), "z", [.command, .option, .shift]),
            submenu("Arrange By", ArrangeOrder.allCases.map {
                item($0.title, #selector(AppDelegate.arrangeNotes(_:)), tag: $0.rawValue)
            }),
            item("Bring All to Front", #selector(AppDelegate.bringAllToFront(_:))),
        ])
        main.addItem(window)
        // AppKit appends the note list (and macOS's tiling items) to this menu.
        NSApp.windowsMenu = window.submenu

        return main
    }

    /// 24×12 pt colour chip, the size of Stickies' swatch asset.
    static func swatch(_ shades: NoteShades) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 12), flipped: false) { rect in
            shades.body.nsColor.setFill()
            rect.fill()
            shades.control.nsColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
        return image
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command,
                             target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.tag = tag
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
