import AppKit
import StickiesCore

/// `StickiesMD --snapshot <dir>`: renders sample notes to PNGs without showing
/// windows, so the look can be checked without Screen Recording permission.
enum Snapshot {
    static let sample = "Groceries\n- milk\n- eggs\nCall Sam at 5"
    static let markdownSample = """
        # Groceries
        - [ ] milk
        - [x] eggs
        - bread
        \t- rye
        1. first
        > a quote
        ---
        **Call** Sam at *5*, ~~not~~ `555-0100`
        """

    static func run(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var cases: [(name: String, color: NotePreset, active: Bool, collapsed: Bool)] = [
            ("yellow-active", .yellow, true, false),
            ("yellow-inactive", .yellow, false, false),
            ("yellow-collapsed", .yellow, true, true),
        ]
        cases += NotePreset.allCases.dropFirst().map { ("\($0.rawValue)-active", $0, true, false) }

        var images: [NSBitmapImageRep] = []
        for item in cases {
            var defaults = NoteDefaults()
            defaults.color = .preset(item.color)
            var note = Note(defaults: defaults, frame: CGRect(x: 200, y: 200, width: 300, height: 200), text: sample)
            note.isCollapsed = item.collapsed
            let controller = NoteWindowController(note: note)
            controller.forceActive = item.active
            guard let rep = render(controller) else { continue }
            try png(rep).write(to: directory.appendingPathComponent(item.name + ".png"))
            images.append(rep)
        }
        // The first-launch welcome notes.
        for (index, note) in WelcomeNotes.make(defaults: NoteDefaults(), visible: CGRect(x: 0, y: 0, width: 1440, height: 900))
            .enumerated() {
            let controller = NoteWindowController(note: note)
            controller.forceActive = index == 1
            if let rep = render(controller) {
                try png(rep).write(to: directory.appendingPathComponent("welcome-\(index).png"))
            }
        }

        // Typora style: the same Markdown rendered, then with its second line being edited.
        for (name, editing) in [("yellow-markdown", nil), ("yellow-markdown-editing", NSRange(location: 12, length: 0))] {
            let note = Note(defaults: NoteDefaults(), frame: CGRect(x: 200, y: 200, width: 300, height: 220),
                            text: markdownSample)
            let controller = NoteWindowController(note: note)
            controller.forceActive = true
            controller.editingOverride = editing
            if let rep = render(controller) {
                try png(rep).write(to: directory.appendingPathComponent(name + ".png"))
                images.append(rep)
            }
        }
        try TextFile.write(markdown: markdownSample, style: Note(defaults: NoteDefaults(), frame: .zero).markdownStyle,
                           as: .plainText, to: directory.appendingPathComponent("yellow-markdown.txt"))

        try png(sheet(images)).write(to: directory.appendingPathComponent("sheet.png"))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: AppDelegate.aboutCredits])
        if let about = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let view = about.contentView,
           let rep = render(view) {
            try png(rep).write(to: directory.appendingPathComponent("about.png"))
            about.orderOut(nil)
        }

        let finder = FindPanelController { [] }
        if let view = finder.window?.contentView, let rep = render(view) {
            try png(rep).write(to: directory.appendingPathComponent("find-panel.png"))
        }

        // What File → Print… produces, saved as a PDF without any panels.
        let note = Note(defaults: NoteDefaults(), frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                        text: markdownSample)
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = directory.appendingPathComponent("print.pdf")
        let operation = NoteWindowController(note: note).makePrintOperation(printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    private static func render(_ controller: NoteWindowController) -> NSBitmapImageRep? {
        controller.window?.contentView.flatMap(render)
    }

    private static func render(_ view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// All renders in a 3-column grid on a light grey background.
    private static func sheet(_ images: [NSBitmapImageRep]) -> NSBitmapImageRep {
        let cell = NSSize(width: 320, height: 220)
        let columns = 3
        let rows = (images.count + columns - 1) / columns
        let size = NSSize(width: cell.width * CGFloat(columns) + 20, height: cell.height * CGFloat(rows) + 20)
        // Keep the renders' backing scale (2× on Retina).
        let scale = images.first.map { CGFloat($0.pixelsWide) / $0.size.width } ?? 1
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                     pixelsHigh: Int(size.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        sheet.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor(white: 0.92, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns, row = index / columns
            let imageSize = image.size
            let top = size.height - 20 - CGFloat(row) * cell.height
            let origin = NSPoint(x: 20 + CGFloat(column) * cell.width, y: top - imageSize.height)
            image.draw(in: NSRect(origin: origin, size: imageSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        return sheet
    }

    private static func png(_ rep: NSBitmapImageRep) -> Data {
        rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
