import CoreGraphics
import Foundation

/// Settings new notes start with. "Use as Default" overwrites them.
public struct NoteDefaults: Codable, Equatable {
    public var color: NoteColor = .preset(.yellow)
    public var fontName = "Helvetica"
    public var fontSize = 12.0
    public var isFloating = false
    public var isTranslucent = false
    public var size = CGSize(width: 300, height: 200)

    public init() {}
}

public struct Note: Codable, Equatable, Identifiable {
    public var id = UUID()
    /// The note's Markdown, saved as `<id>.md` next to the index, not inside the JSON.
    public var text = ""
    /// Expanded frame in screen coordinates, also while collapsed.
    public var frame: CGRect
    public var color: NoteColor
    public var fontName: String
    public var fontSize: Double
    public var isFloating: Bool
    public var isTranslucent: Bool
    public var isCollapsed = false
    public var created = Date()
    public var modified = Date()

    enum CodingKeys: String, CodingKey {
        case id, frame, color, fontName, fontSize
        case isFloating, isTranslucent, isCollapsed, created, modified
    }

    public init(defaults: NoteDefaults, frame: CGRect, text: String = "") {
        self.text = text
        self.frame = frame
        color = defaults.color
        fontName = defaults.fontName
        fontSize = defaults.fontSize
        isFloating = defaults.isFloating
        isTranslucent = defaults.isTranslucent
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum NoteTitle {
    public static let untitled = "Untitled"

    /// First non-empty line without its Markdown markers: the text shown in a
    /// collapsed note's bar, the Window menu and file names.
    public static func of(_ text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let plain = strip(String(line)).trimmingCharacters(in: .whitespaces)
            if !plain.isEmpty { return plain }
        }
        return untitled
    }

    static func strip(_ line: String) -> String {
        var plain = line.replacingOccurrences(
            of: #"^\s*(#{1,6}\s+|>\s?|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        for marker in ["**", "__", "~~", "`", "<u>", "</u>", "*"] {
            plain = plain.replacingOccurrences(of: marker, with: "")
        }
        return plain
    }
}

/// A hard cap on note length so a huge paste or import can't freeze the editor.
public enum NoteLimits {
    /// About 5,000 lines: typing stays under 7 ms a key, loading a fraction of a second.
    public static let maxCharacters = 100_000

    /// Whether replacing `range` with `length` UTF-16 characters keeps a note of `current`
    /// characters within the cap. Edits that shrink the note always pass, so a note that is
    /// already over (from an older version) can still be trimmed.
    public static func allows(replacing range: NSRange, with length: Int, in current: Int) -> Bool {
        let result = current - range.length + length
        return result <= maxCharacters || result <= current
    }

    /// Imported text, cut to the cap. Returns whether anything was cut.
    public static func fitted(_ text: String) -> (text: String, wasCut: Bool) {
        let string = text as NSString
        guard string.length > maxCharacters else { return (text, false) }
        let end = string.rangeOfComposedCharacterSequence(at: maxCharacters).location
        return (string.substring(to: end), true)
    }
}
