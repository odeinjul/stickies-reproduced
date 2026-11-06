import AppKit

/// Rich text → basic Markdown, for File → Export Text… as Markdown.
///
/// Kept: bold, italic, strikethrough, code (monospaced text), links, headings
/// (paragraphs clearly larger than the note's usual size), and underline,
/// superscript and subscript as HTML tags. Dropped: fonts, sizes, colours, kern,
/// ligatures, outline. Text the user typed as Markdown passes through untouched.
public enum MarkdownConverter {
    struct Style: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var underline = false
        var code = false
        var script = 0
        var link: String?
    }

    public static func markdown(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        let baseSize = dominantFontSize(text)
        var lines: [String] = []
        var location = 0
        repeat {
            let paragraph = string.lineRange(for: NSRange(location: location, length: 0))
            var content = paragraph
            while content.length > 0, [10, 13].contains(string.character(at: NSMaxRange(content) - 1)) {
                content.length -= 1
            }
            lines.append(line(text, content, baseSize: baseSize))
            location = NSMaxRange(paragraph)
        } while location < string.length
        return lines.joined(separator: "\n")
    }

    static func line(_ text: NSAttributedString, _ range: NSRange, baseSize: CGFloat) -> String {
        guard range.length > 0 else { return "" }
        var range = range
        var prefix = ""
        let string = text.string as NSString
        // List items: drop the "\t•\t" marker text; write "- " or "1. ", two spaces per level.
        if let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
           let list = style.textLists.last {
            let marker = string.range(of: #"^\t[^\t]*\t"#, options: .regularExpression, range: range)
            if marker.location != NSNotFound {
                range = NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker))
            }
            let indent = String(repeating: "  ", count: style.textLists.count - 1)
            prefix = indent + (list.isOrdered ? "1. " : "- ")
        }
        // ☐ / ☑ checkboxes from notes written before Markdown.
        let first = range.length > 0 ? string.substring(with: NSRange(location: range.location, length: 1)) : ""
        if first == "☐" || first == "☑" {
            prefix += first == "☑" ? "- [x]" : "- [ ]"
            range = NSRange(location: range.location + 1, length: range.length - 1)
            if range.length == 0 { return prefix }
        }
        guard range.length > 0 else { return prefix }
        let level = headingLevel(text, range, baseSize: baseSize)
        var runs: [(style: Style, text: String)] = []
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            var style = style(attributes)
            if level > 0 { style.bold = false } // Headings are bold already.
            let piece = (text.string as NSString).substring(with: runRange)
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += piece
            } else {
                runs.append((style, piece))
            }
        }
        let body = runs.map { wrap($0.text, $0.style) }.joined()
        return prefix + (level > 0 ? String(repeating: "#", count: level) + " " + body : body)
    }

    /// A paragraph is a heading when all its visible text is clearly larger than usual.
    static func headingLevel(_ text: NSAttributedString, _ range: NSRange, baseSize: CGFloat) -> Int {
        var smallest = CGFloat.greatestFiniteMagnitude
        text.enumerateAttribute(.font, in: range) { value, runRange, _ in
            let piece = (text.string as NSString).substring(with: runRange)
            guard let font = value as? NSFont, !piece.allSatisfy(\.isWhitespace) else { return }
            smallest = min(smallest, font.pointSize)
        }
        guard smallest < .greatestFiniteMagnitude else { return 0 }
        if smallest >= baseSize * 1.6 { return 1 }
        if smallest >= baseSize * 1.3 { return 2 }
        if smallest >= baseSize * 1.15 { return 3 }
        return 0
    }

    /// The font size covering the most non-bold characters (headings are bold):
    /// the note's "body" size. A note with only bold text falls back to 12 pt,
    /// Stickies' default, so a lone heading still reads as one.
    static func dominantFontSize(_ text: NSAttributedString) -> CGFloat {
        var regular: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? NSFont, !font.fontDescriptor.symbolicTraits.contains(.bold) else { return }
            regular[font.pointSize, default: 0] += range.length
        }
        return regular.max { $0.value < $1.value }?.key ?? 12
    }

    static func style(_ attributes: [NSAttributedString.Key: Any]) -> Style {
        var style = Style()
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            style.bold = traits.contains(.bold)
            style.italic = traits.contains(.italic)
            style.code = traits.contains(.monoSpace)
        }
        style.strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        style.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        style.script = (attributes[.superscript] as? Int ?? 0).signum()
        if let url = attributes[.link] as? URL {
            style.link = url.absoluteString
        } else if let link = attributes[.link] as? String {
            style.link = link
        }
        return style
    }

    /// Markers hug the text; surrounding spaces stay outside ("**a** b", not "**a **b").
    static func wrap(_ text: String, _ style: Style) -> String {
        let lead = text.prefix { $0.isWhitespace }
        let rest = text.dropFirst(lead.count)
        let trailCount = rest.reversed().prefix { $0.isWhitespace }.count
        var core = String(rest.dropLast(trailCount))
        guard !core.isEmpty else { return text }
        if style.code {
            core = "`\(core)`"
        } else {
            if style.script > 0 { core = "<sup>\(core)</sup>" }
            if style.script < 0 { core = "<sub>\(core)</sub>" }
            if style.underline { core = "<u>\(core)</u>" }
            if style.strike { core = "~~\(core)~~" }
            if style.italic { core = "*\(core)*" }
            if style.bold { core = "**\(core)**" }
        }
        if let link = style.link { core = "[\(core)](\(link))" }
        return String(lead) + core + String(rest.suffix(trailCount))
    }
}
