import AppKit

/// Persists notes as `notes.json` (metadata + defaults) and `notes/<id>.md` (each
/// note's Markdown). Notes from before Markdown (`<id>.rtf` / `<id>.txt`) are
/// converted when loaded; those old files are left in place as a backup.
public struct NoteStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Stickies MD`, or `$STICKIES_MD_DIR` when set. Notes
    /// from when the app was called Stickies Clone move over on first launch.
    public static func standard() -> NoteStore {
        if let path = ProcessInfo.processInfo.environment["STICKIES_MD_DIR"], !path.isEmpty {
            return NoteStore(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Stickies MD", isDirectory: true)
        moveLegacyFolder(from: support.appendingPathComponent("Stickies Clone", isDirectory: true), to: directory)
        return NoteStore(directory: directory)
    }

    /// Moves `old` to `new`, unless `new` already exists or there is nothing to move.
    static func moveLegacyFolder(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    struct Index: Codable {
        var version = 1
        var defaults: NoteDefaults
        var notes: [Note]
    }

    var indexURL: URL { directory.appendingPathComponent("notes.json") }
    var textDirectory: URL { directory.appendingPathComponent("notes", isDirectory: true) }

    public func textURL(for id: UUID) -> URL {
        textDirectory.appendingPathComponent(id.uuidString + ".txt")
    }

    public func richTextURL(for id: UUID) -> URL {
        textDirectory.appendingPathComponent(id.uuidString + ".rtf")
    }

    public func markdownURL(for id: UUID) -> URL {
        textDirectory.appendingPathComponent(id.uuidString + ".md")
    }

    /// False until the first save: the app's first launch.
    public var hasSavedNotes: Bool { FileManager.default.fileExists(atPath: indexURL.path) }

    /// Returns no notes and default settings when nothing has been saved yet.
    public func load() throws -> (notes: [Note], defaults: NoteDefaults) {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return ([], NoteDefaults()) }
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        let notes = index.notes.map { note -> Note in
            var note = note
            note.text = text(for: note.id)
            return note
        }
        return (notes, index.defaults)
    }

    /// `<id>.md`, else the converted `<id>.rtf`, else `<id>.txt`.
    func text(for id: UUID) -> String {
        if let markdown = try? String(contentsOf: markdownURL(for: id), encoding: .utf8) { return markdown }
        if let data = try? Data(contentsOf: richTextURL(for: id)),
           let rich = NSAttributedString(rtf: data, documentAttributes: nil) {
            return MarkdownConverter.markdown(from: rich)
        }
        return (try? String(contentsOf: textURL(for: id), encoding: .utf8)) ?? ""
    }

    /// Writes every note and removes the files of deleted notes.
    public func save(notes: [Note], defaults: NoteDefaults) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: textDirectory, withIntermediateDirectories: true)
        for note in notes {
            try note.text.write(to: markdownURL(for: note.id), atomically: true, encoding: .utf8)
        }
        let keep = Set(notes.map { $0.id.uuidString })
        for name in try fm.contentsOfDirectory(atPath: textDirectory.path)
        where !keep.contains((name as NSString).deletingPathExtension)
            && [".md", ".txt", ".rtf"].contains(where: name.hasSuffix) {
            try fm.removeItem(at: textDirectory.appendingPathComponent(name))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Index(defaults: defaults, notes: notes)).write(to: indexURL, options: .atomic)
    }
}
