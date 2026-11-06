import AppKit

/// Editing commands for Markdown notes, Typora style. Every change goes through
/// the text view, so it is undoable.
public enum MarkdownEditing {
    static let task = MarkdownRenderer.regex(#"^([ \t]*)([-*+])([ \t]+)\[[ xX]\]([ \t]+)"#)
    static let bullet = MarkdownRenderer.regex(#"^([ \t]*)([-*+])([ \t]+)"#)
    static let ordered = MarkdownRenderer.regex(#"^([ \t]*)(\d+)([.)])([ \t]+)"#)
    static let quote = MarkdownRenderer.regex(#"^>[ \t]?"#)

    /// The line around `index`, without its line break.
    static func line(at index: Int, in string: NSString) -> NSRange {
        var line = string.lineRange(for: NSRange(location: min(index, string.length), length: 0))
        while line.length > 0, [10, 13].contains(string.character(at: NSMaxRange(line) - 1)) { line.length -= 1 }
        return line
    }

    /// The list, checklist or quote marker that starts the line, and what the next line's marker is.
    static func listPrefix(of line: NSRange, in string: NSString) -> (prefix: NSRange, next: String)? {
        let text = string as String
        if MarkdownRenderer.rule.firstMatch(in: text, range: line) != nil { return nil }
        if let m = task.firstMatch(in: text, range: line) {
            let next = string.substring(with: m.range(at: 1)) + string.substring(with: m.range(at: 2)) + " [ ] "
            return (m.range, next)
        }
        if let m = bullet.firstMatch(in: text, range: line) {
            return (m.range, string.substring(with: m.range))
        }
        if let m = ordered.firstMatch(in: text, range: line) {
            let number = (Int(string.substring(with: m.range(at: 2))) ?? 0) + 1
            let next = string.substring(with: m.range(at: 1)) + "\(number)" + string.substring(with: m.range(at: 3))
                + string.substring(with: m.range(at: 4))
            return (m.range, next)
        }
        if let m = quote.firstMatch(in: text, range: line) {
            return (m.range, "> ")
        }
        return nil
    }

    /// Return in a list, checklist or quote continues it; on an empty item it
    /// ends it, leaving a plain empty line. Returns true when handled.
    public static func handleNewline(in view: NSTextView) -> Bool {
        let selection = view.selectedRange()
        let string = view.string as NSString
        let line = line(at: selection.location, in: string)
        guard let (prefix, next) = listPrefix(of: line, in: string), selection.location >= NSMaxRange(prefix) else {
            return false
        }
        if NSMaxRange(prefix) == NSMaxRange(line), selection.length == 0 {
            return replace(prefix, with: "", in: view)
        }
        return replace(selection, with: "\n" + next, in: view)
    }

    /// Tab / Shift-Tab in a list line nests it one level deeper or shallower.
    public static func indent(in view: NSTextView, outdent: Bool) -> Bool {
        let selection = view.selectedRange()
        let string = view.string as NSString
        let line = line(at: selection.location, in: string)
        guard listPrefix(of: line, in: string) != nil, string.substring(with: line).hasPrefix(">") == false else {
            return false
        }
        if !outdent {
            return replace(NSRange(location: line.location, length: 0), with: "\t", in: view,
                           select: NSRange(location: selection.location + 1, length: selection.length))
        }
        let text = string.substring(with: line)
        let remove = text.hasPrefix("\t") ? 1 : text.hasPrefix("  ") ? 2 : text.hasPrefix(" ") ? 1 : 0
        guard remove > 0 else { return true }
        return replace(NSRange(location: line.location, length: remove), with: "", in: view,
                       select: NSRange(location: max(line.location, selection.location - remove), length: selection.length))
    }

    /// Option-Tab: start a bulleted list on this line. False if it already is a list.
    public static func startList(in view: NSTextView) -> Bool {
        let selection = view.selectedRange()
        let string = view.string as NSString
        let line = line(at: selection.location, in: string)
        guard listPrefix(of: line, in: string) == nil else { return false }
        return replace(NSRange(location: line.location, length: 0), with: "- ", in: view,
                       select: NSRange(location: selection.location + 2, length: selection.length))
    }

    /// Bold, Italic, Underline, Strikethrough: wraps the selection in markers, or
    /// unwraps it when already wrapped. With no selection, inserts a pair and puts
    /// the insertion point between.
    public static func toggleWrap(_ open: String, _ close: String, in view: NSTextView) {
        let selection = view.selectedRange()
        let string = view.string as NSString
        let openLength = (open as NSString).length
        let closeLength = (close as NSString).length
        if selection.length == 0 {
            replace(selection, with: open + close, in: view,
                    select: NSRange(location: selection.location + openLength, length: 0))
            return
        }
        let selected = string.substring(with: selection)
        let before = NSRange(location: selection.location - openLength, length: openLength)
        let after = NSRange(location: NSMaxRange(selection), length: closeLength)
        // A lone "*" next to "**" is bold, not italic.
        let partOfLonger = open.count == 1 && before.location > 0
            && string.substring(with: NSRange(location: before.location - 1, length: 1)) == open
        if before.location >= 0, NSMaxRange(after) <= string.length, !partOfLonger,
           string.substring(with: before) == open, string.substring(with: after) == close {
            replace(NSRange(location: before.location, length: NSMaxRange(after) - before.location), with: selected,
                    in: view, select: NSRange(location: before.location, length: selection.length))
        } else if selected.hasPrefix(open), selected.hasSuffix(close), selection.length >= openLength + closeLength {
            let inner = (selected as NSString).substring(with: NSRange(location: openLength,
                                                                       length: selection.length - openLength - closeLength))
            replace(selection, with: inner, in: view,
                    select: NSRange(location: selection.location, length: (inner as NSString).length))
        } else {
            replace(selection, with: open + selected + close, in: view,
                    select: NSRange(location: selection.location + openLength, length: selection.length))
        }
    }

    /// Ticks or unticks the checkbox of the line around `index`. False if it isn't a checklist line.
    public static func toggleTask(atLine index: Int, in view: NSTextView) -> Bool {
        let string = view.string as NSString
        let line = line(at: index, in: string)
        guard let match = task.firstMatch(in: view.string, range: line) else { return false }
        let box = NSRange(location: NSMaxRange(match.range(at: 3)) + 1, length: 1)
        let ticked = string.substring(with: box) != " "
        return replace(box, with: ticked ? " " : "x", in: view, select: view.selectedRange())
    }

    @discardableResult
    static func replace(_ range: NSRange, with string: String, in view: NSTextView, select: NSRange? = nil) -> Bool {
        guard view.shouldChangeText(in: range, replacementString: string) else { return false }
        view.textStorage?.replaceCharacters(in: range, with: string)
        view.didChangeText()
        view.setSelectedRange(select ?? NSRange(location: range.location + (string as NSString).length, length: 0))
        return true
    }
}
