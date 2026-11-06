import AppKit
import XCTest
@testable import StickiesCore

final class PaletteTests: XCTestCase {
    /// Yellow and grey are Stickies' exact values; each shade darker than the one before.
    func testPalette() {
        let expected: [NotePreset: [String]] = [
            .yellow: ["#FEF49C", "#FEEA3D", "#DBC503", "#BCA902"],
            .blue: ["#CDE6FF", "#A9D2FC", "#4D9BE6", "#3A84CC"],
            .green: ["#D4F5C4", "#B6EAA0", "#5DB84A", "#4A9C3A"],
            .pink: ["#FFD6DC", "#FFBAC5", "#EF7A8E", "#D4637A"],
            .purple: ["#E3D6FF", "#CDB8FA", "#9A78E0", "#8261C7"],
            .gray: ["#EEEEEE", "#DADADA", "#A8A8A8", "#9E9E9E"],
        ]
        XCTAssertEqual(NotePreset.allCases.count, 6)
        for preset in NotePreset.allCases {
            let s = preset.shades
            XCTAssertEqual([s.body.hex, s.spine.hex, s.control.hex, s.highlight.hex], expected[preset], "\(preset)")
        }
        XCTAssertEqual(NotePreset.gray.title, "Gray")
        for preset in NotePreset.allCases {
            let s = preset.shades
            let brightness = [s.body, s.spine, s.control, s.highlight].map { $0.red + $0.green + $0.blue }
            XCTAssertEqual(brightness, brightness.sorted(by: >), "\(preset) darkens body → highlight")
        }
    }

    func testHexParsing() {
        XCTAssertEqual(RGB(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertEqual(RGB(hex: "ff8000")?.hex, "#FF8000")
        XCTAssertNil(RGB(hex: "#FFF"))
        XCTAssertNil(RGB(hex: "#GGGGGG"))
    }

    /// The Collapse glyph's bar (measured on Stickies) is half control, half body.
    func testCollapseBarIsHalfwayBetweenControlAndBody() {
        for preset in NotePreset.allCases {
            let s = preset.shades
            XCTAssertEqual(s.collapseBar.red, (s.control.red + s.body.red) / 2, accuracy: 0.001)
            XCTAssertEqual(s.collapseBar.blue, (s.control.blue + s.body.blue) / 2, accuracy: 0.001)
        }
    }

    func testCustomShadesGetDarker() {
        let s = NoteShades(custom: RGB(hex: "#80C0FF")!)
        XCTAssertEqual(s.body.hex, "#80C0FF")
        XCTAssertLessThan(s.spine.blue, s.body.blue)
        XCTAssertLessThan(s.control.blue, s.spine.blue)
        XCTAssertLessThan(s.highlight.blue, s.control.blue)
    }

    func testNoteColorCodable() throws {
        let colors: [NoteColor] = [.preset(.pink), .custom(RGB(hex: "#123456")!)]
        let data = try JSONEncoder().encode(colors)
        XCTAssertEqual(String(data: data, encoding: .utf8), ##"["pink","#123456"]"##)
        XCTAssertEqual(try JSONDecoder().decode([NoteColor].self, from: data), colors)
        XCTAssertThrowsError(try JSONDecoder().decode([NoteColor].self, from: Data(#"["teal"]"#.utf8)))
    }
}

final class NoteTests: XCTestCase {
    func testDefaultsMatchNativeStickies() {
        let d = NoteDefaults()
        XCTAssertEqual(d.color, .preset(.yellow))
        XCTAssertEqual(d.fontName, "Helvetica")
        XCTAssertEqual(d.fontSize, 12)
        XCTAssertEqual(d.size, CGSize(width: 300, height: 200))
        XCTAssertFalse(d.isFloating)
        XCTAssertFalse(d.isTranslucent)
    }

    func testCollapsedTitle() {
        XCTAssertEqual(NoteTitle.of("\n   Groceries  \n- milk"), "Groceries")
        XCTAssertEqual(NoteTitle.of(""), "Untitled")
        XCTAssertEqual(NoteTitle.of("  \n\t\n"), "Untitled")
        XCTAssertEqual(NoteTitle.of("one line"), "one line")
    }

    /// Titles come from Markdown without its markers.
    func testTitleDropsMarkdown() {
        XCTAssertEqual(NoteTitle.of("# **Groceries** list"), "Groceries list")
        XCTAssertEqual(NoteTitle.of("- [ ] buy `milk`"), "buy milk")
        XCTAssertEqual(NoteTitle.of("> 1. quoted"), "1. quoted")
        XCTAssertEqual(NoteTitle.of("2. ~~old~~ new"), "old new")
        XCTAssertEqual(NoteTitle.of("#\n\nreal"), "#")
    }

    func testEmptyNote() {
        var note = Note(defaults: NoteDefaults(), frame: .zero)
        XCTAssertTrue(note.isEmpty)
        note.text = " \n "
        XCTAssertTrue(note.isEmpty)
        note.text = "x"
        XCTAssertFalse(note.isEmpty)
    }
}

final class LayoutTests: XCTestCase {
    /// Positions from Stickies' nib (300 pt wide) and a 431 pt screenshot.
    func testButtonPositions() {
        XCTAssertEqual(NoteLayout.closeFrame(width: 300), CGRect(x: 12, y: 2, width: 8, height: 8))
        XCTAssertEqual(NoteLayout.zoomFrame(width: 300).minX, 268)
        XCTAssertEqual(NoteLayout.collapseFrame(width: 300).minX, 280)
        XCTAssertEqual(NoteLayout.zoomFrame(width: 431).minX, 399)
        XCTAssertEqual(NoteLayout.collapseFrame(width: 431).minX, 411)
        XCTAssertEqual(NoteLayout.spineHeight, 12)
        XCTAssertEqual(NoteLayout.translucentAlpha, 0.75)
    }

    func testTitleFitsBetweenButtons() {
        let title = NoteLayout.titleFrame(width: 300)
        XCTAssertGreaterThan(title.minX, NoteLayout.closeFrame(width: 300).maxX)
        XCTAssertLessThan(title.maxX, NoteLayout.zoomFrame(width: 300).minX)
        XCTAssertEqual(NoteLayout.titleFrame(width: 40).width, 0)
    }

    func testResizeLines() {
        let lines = NoteLayout.resizeLines(width: 300)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].start, CGPoint(x: 290, y: 2))
        XCTAssertEqual(lines[0].end, CGPoint(x: 298, y: 10))
        XCTAssertEqual(lines[2].start, CGPoint(x: 296, y: 2))
        XCTAssertEqual(lines[2].end, CGPoint(x: 298, y: 4))
    }

    func testCollapseKeepsTopEdge() {
        let frame = CGRect(x: 100, y: 300, width: 300, height: 200)
        let collapsed = NoteLayout.collapsedFrame(from: frame)
        XCTAssertEqual(collapsed, CGRect(x: 100, y: 488, width: 300, height: 12))
        XCTAssertEqual(NoteLayout.expandedFrame(from: collapsed, height: 200), frame)
    }

    /// Native: Zoom fills the screen; Collapse then leaves a full-width bar at the top.
    func testCollapsingZoomedNoteLeavesTopBar() {
        let visible = CGRect(x: 0, y: 70, width: 1800, height: 1050)
        let bar = NoteLayout.collapsedFrame(from: visible)
        XCTAssertEqual(bar, CGRect(x: 0, y: 1108, width: 1800, height: 12))
        XCTAssertEqual(bar.maxY, visible.maxY)
        XCTAssertEqual(NoteLayout.expandedFrame(from: bar, height: visible.height), visible)
    }
}

final class StoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadWithNothingSaved() throws {
        let loaded = try NoteStore(directory: directory).load()
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertEqual(loaded.defaults, NoteDefaults())
    }

    func testRoundTrip() throws {
        let store = NoteStore(directory: directory)
        var defaults = NoteDefaults()
        defaults.color = .preset(.green)
        defaults.isFloating = true
        var a = Note(defaults: defaults, frame: CGRect(x: 10, y: 20, width: 300, height: 200), text: "# Hello\n- world 🙂")
        a.isTranslucent = true
        a.isCollapsed = true
        var b = Note(defaults: NoteDefaults(), frame: CGRect(x: 50, y: 60, width: 120, height: 90), text: "")
        b.color = .custom(RGB(hex: "#336699")!)

        try store.save(notes: [a, b], defaults: defaults)
        let loaded = try store.load()
        XCTAssertEqual(loaded.notes, [a, b])
        XCTAssertEqual(loaded.defaults, defaults)
        // Each note is a plain Markdown file.
        XCTAssertEqual(try String(contentsOf: store.markdownURL(for: a.id), encoding: .utf8), "# Hello\n- world 🙂")
    }

    /// Notes from before Markdown: RTF converts to Markdown, plain text stays; old files stay as a backup.
    func testOlderNotesConvertToMarkdown() throws {
        let store = NoteStore(directory: directory)
        let rich = Note(defaults: NoteDefaults(), frame: .zero)
        let plain = Note(defaults: NoteDefaults(), frame: .zero)
        try store.save(notes: [rich, plain], defaults: NoteDefaults())
        try FileManager.default.removeItem(at: store.markdownURL(for: rich.id))
        try FileManager.default.removeItem(at: store.markdownURL(for: plain.id))
        let bold = NSFontManager.shared.convert(NSFont(name: "Helvetica", size: 12)!, toHaveTrait: .boldFontMask)
        let text = NSMutableAttributedString(string: "Buy ", attributes: [.font: NSFont(name: "Helvetica", size: 12)!])
        text.append(NSAttributedString(string: "milk", attributes: [.font: bold]))
        try text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
            .write(to: store.richTextURL(for: rich.id))
        try "old plain".write(to: store.textURL(for: plain.id), atomically: true, encoding: .utf8)

        let loaded = try store.load()
        XCTAssertEqual(loaded.notes.map(\.text), ["Buy **milk**", "old plain"])
        try store.save(notes: loaded.notes, defaults: loaded.defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.markdownURL(for: rich.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.richTextURL(for: rich.id).path), "kept as a backup")
    }

    func testDeletedNotesLoseTheirFiles() throws {
        let store = NoteStore(directory: directory)
        let a = Note(defaults: NoteDefaults(), frame: .zero, text: "a")
        let b = Note(defaults: NoteDefaults(), frame: .zero, text: "b")
        try store.save(notes: [a, b], defaults: NoteDefaults())
        try "old".write(to: store.textURL(for: a.id), atomically: true, encoding: .utf8)
        try store.save(notes: [b], defaults: NoteDefaults())
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: store.markdownURL(for: a.id).path))
        XCTAssertFalse(fm.fileExists(atPath: store.textURL(for: a.id).path))
        XCTAssertEqual(try store.load().notes.map(\.text), ["b"])
    }
}

final class TextFileTests: XCTestCase {
    func testTextRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try TextFile.write("Line 1\nLíne 2 ✓", to: url)
        XCTAssertEqual(try TextFile.read(url), "Line 1\nLíne 2 ✓")
    }

    func testNotesExportFoldersByColor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let yellow = Note(defaults: NoteDefaults(), frame: .zero, text: "# Todo\n- **a**")
        var yellowTwin = yellow
        yellowTwin.id = UUID()
        var blue = yellow
        blue.id = UUID()
        blue.color = .preset(.blue)
        blue.text = "a/b: c"
        var custom = yellow
        custom.id = UUID()
        custom.color = .custom(RGB(hex: "#101010")!)
        let empty = Note(defaults: NoteDefaults(), frame: .zero, text: "   ")

        let written = try NotesExport.write([yellow, yellowTwin, blue, custom, empty], to: root)
        let paths = written.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        XCTAssertEqual(paths, ["Yellow/Todo.rtf", "Yellow/Todo 2.rtf", "Blue/a-b- c.rtf", "Custom/Todo.rtf"])
        // Notes gets the note as it looks: formatted, markers gone.
        let rtf = try TextFile.readRich(root.appendingPathComponent("Yellow/Todo.rtf"))
        XCTAssertEqual(rtf.string, "Todo\n• a")
        let font = rtf.attribute(.font, at: (rtf.string as NSString).length - 1, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}

final class FormatTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Same order as Stickies' Format popup, plus Markdown.
    func testFormatsAndExtensions() {
        XCTAssertEqual(TextFormat.allCases.map(\.title), ["RTFD", "RTF", "Plain Text", "Markdown"])
        XCTAssertEqual(TextFormat.markdown.contentType.preferredFilenameExtension, "md")
        XCTAssertEqual(TextFormat(fileURL: URL(fileURLWithPath: "/a/b.RTF")), .rtf)
        XCTAssertEqual(TextFormat(fileURL: URL(fileURLWithPath: "/a/b.rtfd")), .rtfd)
        XCTAssertEqual(TextFormat(fileURL: URL(fileURLWithPath: "/a/b.md")), .markdown)
        XCTAssertEqual(TextFormat(fileURL: URL(fileURLWithPath: "/a/b.log")), .plainText)
    }

    /// Markdown exports as typed; the others as the note looks; import turns it back into Markdown.
    func testEveryFormatRoundTrips() throws {
        let markdown = "Plain **bold**"
        let style = Note(defaults: NoteDefaults(), frame: .zero).markdownStyle
        for format in TextFormat.allCases {
            let url = directory.appendingPathComponent("note").appendingPathExtension(
                format.contentType.preferredFilenameExtension ?? "txt")
            try TextFile.write(markdown: markdown, style: style, as: format, to: url)
            switch format {
            case .rtf, .rtfd:
                let back = try TextFile.readRich(url)
                XCTAssertEqual(back.string, "Plain bold", "\(format)")
                let font = back.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
                XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "\(format) keeps bold")
                XCTAssertEqual(try TextFile.readMarkdown(url), markdown, "\(format) imports as Markdown")
            case .plainText:
                XCTAssertEqual(try TextFile.read(url), "Plain bold")
            case .markdown:
                XCTAssertEqual(try TextFile.readMarkdown(url), markdown)
            }
        }
        // RTFD is a folder package; writing again replaces it.
        let rtfd = directory.appendingPathComponent("note.rtfd")
        try TextFile.write(markdown: markdown, style: style, as: .rtfd, to: rtfd)
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: rtfd.path, isDirectory: &isFolder) && isFolder.boolValue)
    }

    /// Notes are text only: pictures in imported RTFD are dropped.
    func testAttachmentsAreRemoved() {
        let text = NSMutableAttributedString(string: "a")
        text.append(NSAttributedString(attachment: NSTextAttachment()))
        text.append(NSAttributedString(string: "b"))
        TextFile.removeAttachments(text)
        XCTAssertEqual(text.string, "ab")
    }
}

final class MarkdownTests: XCTestCase {
    private let base = NSFont(name: "Helvetica", size: 12)!

    private func run(_ string: String, _ extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: base].merging(extra) { $1 })
    }

    private func markdown(_ parts: NSAttributedString...) -> String {
        let text = NSMutableAttributedString()
        parts.forEach(text.append)
        return MarkdownConverter.markdown(from: text)
    }

    private func font(_ trait: NSFontTraitMask) -> NSFont { NSFontManager.shared.convert(base, toHaveTrait: trait) }

    func testTypedMarkdownPassesThrough() {
        XCTAssertEqual(markdown(run("# Todo\n- [ ] milk\n\n**done**")), "# Todo\n- [ ] milk\n\n**done**")
        XCTAssertEqual(markdown(run("")), "")
    }

    func testInlineStyles() {
        XCTAssertEqual(markdown(run("a "), run("bold", [.font: font(.boldFontMask)]), run(" b")), "a **bold** b")
        XCTAssertEqual(markdown(run("italic", [.font: font(.italicFontMask)])), "*italic*")
        XCTAssertEqual(markdown(run("both", [.font: font([.boldFontMask, .italicFontMask])])), "***both***")
        XCTAssertEqual(markdown(run("gone", [.strikethroughStyle: 1])), "~~gone~~")
        XCTAssertEqual(markdown(run("under", [.underlineStyle: 1])), "<u>under</u>")
        XCTAssertEqual(markdown(run("x"), run("2", [.superscript: 1]), run(" H"), run("2", [.superscript: -1])),
                       "x<sup>2</sup> H<sub>2</sub>")
        XCTAssertEqual(markdown(run("let x", [.font: NSFont.userFixedPitchFont(ofSize: 12)!])), "`let x`")
        XCTAssertEqual(markdown(run("site", [.link: URL(string: "https://example.com")!])), "[site](https://example.com)")
    }

    func testSpacesStayOutsideMarkers() {
        XCTAssertEqual(markdown(run(" bold ", [.font: font(.boldFontMask)]), run("x")), " **bold** x")
    }

    /// Runs that differ only in dropped attributes (here colour) merge.
    func testRunsMerge() {
        let bold = font(.boldFontMask)
        XCTAssertEqual(markdown(run("ab", [.font: bold, .foregroundColor: NSColor.red]),
                                run("cd", [.font: bold, .foregroundColor: NSColor.blue])), "**abcd**")
    }

    func testHeadingsFromLargeText() {
        let text = markdown(run("Title\n", [.font: NSFont(name: "Helvetica-Bold", size: 24)!]),
                            run("Sub\n", [.font: NSFont(name: "Helvetica-Bold", size: 16)!]),
                            run("body text that is the usual size"))
        XCTAssertEqual(text, "# Title\n## Sub\nbody text that is the usual size")
    }

    /// A note that is large all over has no headings: size is relative to the note.
    func testUniformLargeTextIsNotAHeading() {
        let big = NSFont(name: "Helvetica", size: 24)!
        XCTAssertEqual(markdown(run("one\ntwo", [.font: big])), "one\ntwo")
    }
}

final class ResizeTests: XCTestCase {
    private let start = CGRect(x: 100, y: 100, width: 300, height: 200)

    func testEachEdgeKeepsTheOppositeEdge() {
        XCTAssertEqual(NoteLayout.resized(start, edges: .left, dx: -50, dy: 0), CGRect(x: 50, y: 100, width: 350, height: 200))
        XCTAssertEqual(NoteLayout.resized(start, edges: .right, dx: 50, dy: 0), CGRect(x: 100, y: 100, width: 350, height: 200))
        XCTAssertEqual(NoteLayout.resized(start, edges: .top, dx: 0, dy: 40), CGRect(x: 100, y: 100, width: 300, height: 240))
        XCTAssertEqual(NoteLayout.resized(start, edges: .bottom, dx: 0, dy: -40), CGRect(x: 100, y: 60, width: 300, height: 240))
        XCTAssertEqual(NoteLayout.resized(start, edges: [.left, .top], dx: 10, dy: 10), CGRect(x: 110, y: 100, width: 290, height: 210))
    }

    func testMinimumSize() {
        let tiny = NoteLayout.resized(start, edges: [.left, .bottom], dx: 1000, dy: 1000)
        XCTAssertEqual(tiny.size, NoteLayout.minSize)
        XCTAssertEqual(tiny.maxX, start.maxX)
        XCTAssertEqual(tiny.maxY, start.maxY)
    }
}

final class ArrangeTests: XCTestCase {
    private func note(_ text: String, _ color: NotePreset, x: CGFloat, top: CGFloat, modified: TimeInterval) -> Note {
        var n = Note(defaults: NoteDefaults(), frame: CGRect(x: x, y: top - 200, width: 300, height: 200), text: text)
        n.color = .preset(color)
        n.modified = Date(timeIntervalSinceReferenceDate: modified)
        return n
    }

    func testSortOrders() {
        let a = note("banana", .pink, x: 500, top: 900, modified: 3)
        let b = note("Apple", .yellow, x: 100, top: 900, modified: 1)
        let c = note("cherry", .blue, x: 50, top: 400, modified: 2)
        var d = note("apple pie", .yellow, x: 0, top: 950, modified: 4)
        d.color = .custom(RGB(hex: "#123456")!)
        let notes = [a, b, c, d]
        func texts(_ order: ArrangeOrder) -> [String] { NoteArrange.sorted(notes, by: order).map(\.text) }
        XCTAssertEqual(texts(.color), ["Apple", "cherry", "banana", "apple pie"])
        XCTAssertEqual(texts(.content), ["Apple", "apple pie", "banana", "cherry"])
        XCTAssertEqual(texts(.date), ["Apple", "cherry", "banana", "apple pie"])
        XCTAssertEqual(texts(.location), ["apple pie", "Apple", "banana", "cherry"])
        XCTAssertEqual(ArrangeOrder.allCases.map(\.title), ["Color", "Content", "Date", "Location on Screen"])
    }

    /// Measured from Stickies: start 8 pt in, 16 pt down; bars touch; new column below y = 100.
    func testArrangedFramesStackBars() {
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 160)
        let frames = NoteLayout.arrangedFrames(widths: [300, 250, 300, 300, 300], in: visible)
        XCTAssertEqual(frames[0], CGRect(x: 8, y: 144, width: 300, height: 12))
        XCTAssertEqual(frames[1], CGRect(x: 8, y: 132, width: 250, height: 12))
        XCTAssertEqual(frames[3].minY, 108)
        XCTAssertEqual(frames[4], CGRect(x: 208, y: 144, width: 300, height: 12))
    }
}

final class SearchTests: XCTestCase {
    func testMatchForwardBackwardAndWrap() {
        let text = "cat Cat cat"
        XCTAssertEqual(TextSearch.match(of: "cat", in: text, from: 1, forward: true, ignoreCase: true, wraps: false),
                       NSRange(location: 4, length: 3))
        XCTAssertEqual(TextSearch.match(of: "cat", in: text, from: 1, forward: true, ignoreCase: false, wraps: false),
                       NSRange(location: 8, length: 3))
        XCTAssertEqual(TextSearch.match(of: "cat", in: text, from: 8, forward: false, ignoreCase: true, wraps: false),
                       NSRange(location: 4, length: 3))
        XCTAssertNil(TextSearch.match(of: "cat", in: text, from: 11, forward: true, ignoreCase: true, wraps: false))
        XCTAssertEqual(TextSearch.match(of: "cat", in: text, from: 11, forward: true, ignoreCase: true, wraps: true),
                       NSRange(location: 0, length: 3))
        XCTAssertNil(TextSearch.match(of: "", in: text, from: 0, forward: true, ignoreCase: true, wraps: true))
    }

    func testRangesForReplaceAll() {
        XCTAssertEqual(TextSearch.ranges(of: "aa", in: "aaaa Aa", ignoreCase: true).map(\.location), [0, 2, 5])
        XCTAssertEqual(TextSearch.ranges(of: "aa", in: "aaaa Aa", ignoreCase: false).count, 2)
    }

    func testAcrossNotesWrapsBackToStart() {
        let texts = ["milk here", "no", "more milk"]
        let next = TextSearch.match(of: "milk", in: texts, note: 0, from: 4, forward: true, ignoreCase: true)
        XCTAssertEqual(next?.note, 2)
        XCTAssertEqual(next?.range, NSRange(location: 5, length: 4))
        let wrapped = TextSearch.match(of: "milk", in: texts, note: 2, from: 9, forward: true, ignoreCase: true)
        XCTAssertEqual(wrapped?.note, 0)
        let back = TextSearch.match(of: "milk", in: texts, note: 0, from: 0, forward: false, ignoreCase: true)
        XCTAssertEqual(back?.note, 2)
        XCTAssertNil(TextSearch.match(of: "eggs", in: texts, note: 1, from: 0, forward: true, ignoreCase: true))
    }
}

final class RendererTests: XCTestCase {
    private let style = MarkdownStyle(font: NSFont(name: "Helvetica", size: 12)!, textColor: .black)

    private func render(_ text: String, editing: NSRange? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownRenderer.render(storage, style: style, editing: editing)
        return storage
    }

    private func hidden(_ s: NSTextStorage, _ i: Int) -> Bool { s.attribute(.markdownHidden, at: i, effectiveRange: nil) != nil }
    private func font(_ s: NSTextStorage, _ i: Int) -> NSFont { s.attribute(.font, at: i, effectiveRange: nil) as! NSFont }
    private func traits(_ s: NSTextStorage, _ i: Int) -> NSFontDescriptor.SymbolicTraits { font(s, i).fontDescriptor.symbolicTraits }
    private func decoration(_ s: NSTextStorage, _ i: Int) -> MarkdownDecoration? {
        (s.attribute(.markdownDecoration, at: i, effectiveRange: nil) as? String).flatMap(MarkdownDecoration.init(rawValue:))
    }
    private func indent(_ s: NSTextStorage, _ i: Int) -> CGFloat {
        (s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
    }

    func testHeadingHidesMarkersUnlessEditing() {
        let s = render("# Title\nbody")
        XCTAssertTrue(hidden(s, 0) && hidden(s, 1))
        XCTAssertFalse(hidden(s, 2))
        XCTAssertEqual(font(s, 2).pointSize, 12 * 1.8, accuracy: 0.01)
        XCTAssertTrue(traits(s, 2).contains(.bold))
        XCTAssertEqual(font(s, 8).pointSize, 12)

        let editing = render("# Title\nbody", editing: NSRange(location: 3, length: 0))
        XCTAssertFalse(hidden(editing, 0), "the line being edited shows its markers")
        XCTAssertEqual(font(editing, 2).pointSize, 12 * 1.8, accuracy: 0.01)
        XCTAssertEqual(editing.string, "# Title\nbody", "rendering never changes the text")
    }

    func testInlineMarkersHideAndStyle() {
        let text = "a **b** *c* ~~d~~ `e` <u>f</u> [g](http://x.y)"
        let s = render(text)
        let string = text as NSString
        func at(_ sub: String) -> Int { string.range(of: sub).location }
        XCTAssertTrue(hidden(s, at("**")))
        XCTAssertTrue(traits(s, at("b")).contains(.bold))
        XCTAssertTrue(traits(s, at("c")).contains(.italic))
        XCTAssertEqual(s.attribute(.strikethroughStyle, at: at("d"), effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertTrue(traits(s, at("e")).contains(.monoSpace))
        XCTAssertEqual(s.attribute(.underlineStyle, at: at("f"), effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertTrue(hidden(s, at("<u>")) && hidden(s, at("](http")))
        XCTAssertFalse(hidden(s, at("g")))
    }

    func testListsCheckboxesQuotesAndRules() {
        let text = "- milk\n- [ ] eggs\n- [x] jam\n\t- rye\n1. one\n> q\n---"
        let s = render(text)
        let string = text as NSString
        func at(_ sub: String) -> Int { string.range(of: sub).location }
        XCTAssertEqual(decoration(s, 0), .bullet)
        XCTAssertEqual(indent(s, at("milk")), 18)
        XCTAssertEqual(decoration(s, at("- [ ]")), .unchecked)
        XCTAssertEqual(decoration(s, at("- [x]")), .checked)
        XCTAssertNotEqual(s.attribute(.foregroundColor, at: at("jam"), effectiveRange: nil) as? NSColor, .black, "ticked items dim")
        XCTAssertEqual(indent(s, at("rye")), 36, "nested one level")
        XCTAssertFalse(hidden(s, at("1.")), "numbers stay visible")
        XCTAssertEqual(decoration(s, at("> ")), .quote)
        XCTAssertEqual(decoration(s, at("---")), .rule)
    }

    func testCodeFenceIsLiteral() {
        let text = "```\n**not bold**\n```"
        let s = render(text)
        XCTAssertTrue(traits(s, 6).contains(.monoSpace))
        XCTAssertFalse(hidden(s, 4), "markers inside code stay")
        XCTAssertFalse(traits(s, 6).contains(.bold))
    }

    /// Print, RTF and Notes get the note as it looks.
    func testRenderedWithoutMarkers() {
        let rendered = MarkdownRenderer.rendered("# T\n- a\n\t- b\n- [x] c\n**d**\n---", style: style)
        XCTAssertEqual(rendered.string, "T\n• a\n• b\n☑ c\nd\n———")
    }
}

final class EditingTests: XCTestCase {
    private var view: NSTextView!

    override func setUp() {
        view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.isRichText = false
        view.allowsUndo = true
    }

    private func set(_ text: String, caret: Int? = nil) {
        view.string = text
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
    }

    private func newline() -> Bool { MarkdownEditing.handleNewline(in: view) }

    func testReturnContinuesListsAndEndsOnAnEmptyItem() {
        set("- milk"); XCTAssertTrue(newline()); XCTAssertEqual(view.string, "- milk\n- ")
        XCTAssertTrue(newline()); XCTAssertEqual(view.string, "- milk\n", "Return on an empty item ends the list")
        set("- [x] done"); _ = newline(); XCTAssertEqual(view.string, "- [x] done\n- [ ] ")
        set("\t* sub"); _ = newline(); XCTAssertEqual(view.string, "\t* sub\n\t* ")
        set("9. nine"); _ = newline(); XCTAssertEqual(view.string, "9. nine\n10. ")
        set("> quote"); _ = newline(); XCTAssertEqual(view.string, "> quote\n> ")
        set("- milk", caret: 3); _ = newline(); XCTAssertEqual(view.string, "- m\n- ilk", "splits the item")
        set("plain"); XCTAssertFalse(newline())
        set("---"); XCTAssertFalse(newline())
        set("- milk", caret: 1); XCTAssertFalse(newline(), "inside the marker")
    }

    func testTabNestsListLines() {
        set("- a")
        XCTAssertTrue(MarkdownEditing.indent(in: view, outdent: false)); XCTAssertEqual(view.string, "\t- a")
        XCTAssertTrue(MarkdownEditing.indent(in: view, outdent: true)); XCTAssertEqual(view.string, "- a")
        set("plain"); XCTAssertFalse(MarkdownEditing.indent(in: view, outdent: false))
    }

    func testOptionTabStartsAList() {
        set("milk")
        XCTAssertTrue(MarkdownEditing.startList(in: view))
        XCTAssertEqual(view.string, "- milk")
        XCTAssertEqual(view.selectedRange().location, 6)
        XCTAssertFalse(MarkdownEditing.startList(in: view), "already a list")
    }

    func testBoldItalicWrapAndUnwrap() {
        set("make bold now"); view.setSelectedRange(NSRange(location: 5, length: 4))
        MarkdownEditing.toggleWrap("**", "**", in: view)
        XCTAssertEqual(view.string, "make **bold** now")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 7, length: 4))
        MarkdownEditing.toggleWrap("**", "**", in: view)
        XCTAssertEqual(view.string, "make bold now")

        set("**bold**"); view.setSelectedRange(NSRange(location: 0, length: 8))
        MarkdownEditing.toggleWrap("**", "**", in: view)
        XCTAssertEqual(view.string, "bold", "selection including the markers unwraps")

        set("**bold**"); view.setSelectedRange(NSRange(location: 2, length: 4))
        MarkdownEditing.toggleWrap("*", "*", in: view)
        XCTAssertEqual(view.string, "***bold***", "italic inside bold, not unwrapping it")

        set("x"); MarkdownEditing.toggleWrap("~~", "~~", in: view)
        XCTAssertEqual(view.string, "x~~~~")
        XCTAssertEqual(view.selectedRange().location, 3)
    }

    func testCheckboxClickToggles() {
        set("- [ ] milk\n- [x] eggs")
        XCTAssertTrue(MarkdownEditing.toggleTask(atLine: 0, in: view))
        XCTAssertEqual(view.string, "- [x] milk\n- [x] eggs")
        XCTAssertTrue(MarkdownEditing.toggleTask(atLine: 12, in: view))
        XCTAssertEqual(view.string, "- [x] milk\n- [ ] eggs")
        set("- milk"); XCTAssertFalse(MarkdownEditing.toggleTask(atLine: 0, in: view))
    }

    func testEditsAreUndoable() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView = view
        let undo = try XCTUnwrap(view.undoManager)
        undo.groupsByEvent = false
        set("- [ ] milk")
        undo.beginUndoGrouping()
        _ = MarkdownEditing.toggleTask(atLine: 0, in: view)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "- [x] milk")
        undo.undo()
        XCTAssertEqual(view.string, "- [ ] milk")
    }
}

final class LimitTests: XCTestCase {
    func testEditsStopAtTheCap() {
        let max = NoteLimits.maxCharacters
        XCTAssertTrue(NoteLimits.allows(replacing: NSRange(location: 0, length: 0), with: 1, in: max - 1))
        XCTAssertFalse(NoteLimits.allows(replacing: NSRange(location: 0, length: 0), with: 1, in: max))
        XCTAssertTrue(NoteLimits.allows(replacing: NSRange(location: 0, length: 5), with: 5, in: max), "same length")
        XCTAssertFalse(NoteLimits.allows(replacing: NSRange(location: 0, length: 0), with: 2, in: max - 1), "paste too big")
        XCTAssertTrue(NoteLimits.allows(replacing: NSRange(location: 0, length: 10), with: 0, in: max + 500),
                      "an over-long note can still be trimmed")
    }

    func testImportIsCutAtTheCap() {
        let short = NoteLimits.fitted("hello")
        XCTAssertEqual(short.text, "hello")
        XCTAssertFalse(short.wasCut)
        let long = NoteLimits.fitted(String(repeating: "ab", count: NoteLimits.maxCharacters))
        XCTAssertEqual((long.text as NSString).length, NoteLimits.maxCharacters)
        XCTAssertTrue(long.wasCut)
        // Never splits an emoji in half.
        let emoji = NoteLimits.fitted(String(repeating: "a", count: NoteLimits.maxCharacters - 1) + "🙂🙂")
        XCTAssertTrue(emoji.text.hasSuffix("a"))
    }
}

final class RenameTests: XCTestCase {
    /// Notes saved under the old app name move to the new folder once; an existing new folder is left alone.
    func testLegacyFolderMovesOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("Stickies Clone"), new = root.appendingPathComponent("Stickies MD")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "x".write(to: old.appendingPathComponent("notes.json"), atomically: true, encoding: .utf8)

        NoteStore.moveLegacyFolder(from: old, to: new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("notes.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))

        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        NoteStore.moveLegacyFolder(from: old, to: new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path), "never overwrites the new folder")
    }
}

final class WelcomeTests: XCTestCase {
    /// Stickies' welcome layout: blue behind at (48, top − 40), yellow in front 21 pt right, 22 pt lower.
    func testWelcomeNotesFollowStickies() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notes = WelcomeNotes.make(defaults: NoteDefaults(), visible: visible)
        XCTAssertEqual(notes.map(\.color), [.preset(.blue), .preset(.yellow)])
        XCTAssertEqual(notes[0].frame, CGRect(x: 48, y: 592, width: 355, height: 268))
        XCTAssertEqual(notes[1].frame, CGRect(x: 69, y: 578, width: 352, height: 260))
        XCTAssertEqual(NoteTitle.of(notes[1].text), "Make a note of it!")
        XCTAssertTrue(notes.allSatisfy { ($0.text as NSString).length < NoteLimits.maxCharacters })
    }

    func testFirstLaunchIsBeforeTheFirstSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        XCTAssertFalse(store.hasSavedNotes)
        try store.save(notes: [], defaults: NoteDefaults())
        XCTAssertTrue(store.hasSavedNotes, "deleting every note later doesn't bring the welcome notes back")
    }
}
