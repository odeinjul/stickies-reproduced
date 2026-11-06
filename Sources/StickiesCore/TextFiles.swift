import AppKit
import UniformTypeIdentifiers

/// The formats File → Export Text… offers: Stickies' three, plus Markdown.
public enum TextFormat: String, CaseIterable {
    case rtfd, rtf, plainText, markdown

    public var title: String {
        switch self {
        case .rtfd: return "RTFD"
        case .rtf: return "RTF"
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        }
    }

    public var contentType: UTType {
        switch self {
        case .rtfd: return .rtfd
        case .rtf: return .rtf
        case .plainText: return .plainText
        case .markdown: return UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
        }
    }

    /// Picks the format from a file's extension; anything unknown reads as plain text.
    public init(fileURL url: URL) {
        switch url.pathExtension.lowercased() {
        case "rtfd": self = .rtfd
        case "rtf": self = .rtf
        case "md", "markdown": self = .markdown
        default: self = .plainText
        }
    }
}

/// File → Import Text… / Export Text….
public enum TextFile {
    /// Reads UTF-8, falling back to whatever encoding Foundation detects.
    public static func read(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    public static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads any supported format. Plain text and Markdown come back unstyled
    /// (Markdown keeps its markers as typed). Pictures in RTFD are dropped:
    /// notes hold text only.
    public static func readRich(_ url: URL) throws -> NSAttributedString {
        switch TextFormat(fileURL: url) {
        case .plainText, .markdown:
            return NSAttributedString(string: try read(url))
        case .rtf, .rtfd:
            let text = try NSMutableAttributedString(url: url, options: [:], documentAttributes: nil)
            removeAttachments(text)
            return text
        }
    }

    /// File → Import Text…: a note's Markdown. RTF and RTFD formatting becomes Markdown.
    public static func readMarkdown(_ url: URL) throws -> String {
        let text = try readRich(url)
        switch TextFormat(fileURL: url) {
        case .rtf, .rtfd: return MarkdownConverter.markdown(from: text)
        case .plainText, .markdown: return text.string
        }
    }

    /// File → Export Text…: Markdown as is; the others as the note looks, markers gone.
    public static func write(markdown: String, style: MarkdownStyle, as format: TextFormat, to url: URL) throws {
        if format == .markdown { return try write(markdown, to: url) }
        let text = MarkdownRenderer.rendered(markdown, style: style)
        let range = NSRange(location: 0, length: text.length)
        switch format {
        case .plainText, .markdown:
            try write(text.string, to: url)
        case .rtf:
            let data = try text.data(from: range,
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url, options: .atomic)
        case .rtfd:
            let wrapper = try text.fileWrapper(from: range,
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            // RTFD is a folder; the save panel has already confirmed replacing it.
            try? FileManager.default.removeItem(at: url)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        }
    }

    static func removeAttachments(_ text: NSMutableAttributedString) {
        var ranges: [NSRange] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        for range in ranges.reversed() { text.deleteCharacters(in: range) }
    }
}

/// File → Export All to Notes…: one `.rtf` per note (the note as it looks, so
/// Notes keeps its formatting) in a folder per colour, which Notes imports into
/// "Imported Notes".
public enum NotesExport {
    /// Skips empty notes. Returns the files written.
    @discardableResult
    public static func write(_ notes: [Note], to root: URL) throws -> [URL] {
        let fm = FileManager.default
        var used = Set<String>()
        var written: [URL] = []
        for note in notes where !note.isEmpty {
            let folder = root.appendingPathComponent(note.color.folderName, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = fileName(for: NoteTitle.of(note.text))
            var name = base
            var counter = 2
            while used.contains(folder.path + "/" + name) {
                name = "\(base) \(counter)"
                counter += 1
            }
            used.insert(folder.path + "/" + name)
            let url = folder.appendingPathComponent(name + ".rtf")
            try TextFile.write(markdown: note.text, style: note.markdownStyle, as: .rtf, to: url)
            written.append(url)
        }
        return written
    }

    static func fileName(for title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return String(cleaned.prefix(60))
    }
}
