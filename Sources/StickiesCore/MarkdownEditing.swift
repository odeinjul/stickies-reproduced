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
    /// the insertion point between. Each line is wrapped on its own, after its list,
    /// quote or heading marker, so the line keeps its checkbox or bullet.
    public static func toggleWrap(_ open: String, _ close: String, in view: NSTextView) {
        let selection = view.selectedRange()
        if selection.length == 0 {
            replace(selection, with: open + close, in: view,
                    select: NSRange(location: selection.location + (open as NSString).length, length: 0))
            return
        }
        let string = view.string as NSString
        var parts: [NSRange] = []
        string.enumerateSubstrings(in: string.lineRange(for: selection), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let marker = listPrefix(of: line, in: string)?.prefix
                ?? MarkdownRenderer.heading.firstMatch(in: string as String, range: line)?.range
            var start = max(NSMaxRange(marker ?? NSRange(location: line.location, length: 0)), selection.location)
            var end = min(NSMaxRange(line), NSMaxRange(selection))
            while start < end, [9, 32].contains(string.character(at: start)) { start += 1 }
            while end > start, [9, 32].contains(string.character(at: end - 1)) { end -= 1 }
            if end > start { parts.append(NSRange(location: start, length: end - start)) }
        }
        // Last line first, so earlier ranges stay put; then select from the first line to the last.
        var first = selection, last = selection, lengthAfterLast = 0
        for (index, part) in parts.enumerated().reversed() {
            first = toggleWrap(open, close, part, in: view)
            if index == parts.count - 1 { last = first; lengthAfterLast = (view.string as NSString).length }
        }
        guard !parts.isEmpty else { return }
        let end = NSMaxRange(last) + (view.string as NSString).length - lengthAfterLast
        view.setSelectedRange(NSRange(location: first.location, length: end - first.location))
    }

    /// Toggles the markers around one line's text and returns where that text is now.
    private static func toggleWrap(_ open: String, _ close: String, _ text: NSRange, in view: NSTextView) -> NSRange {
        let string = view.string as NSString
        let openLength = (open as NSString).length
        let closeLength = (close as NSString).length
        // Take in markers just outside the text, but not a "*" that is half of "**".
        func isMarker(_ marker: String, at location: Int) -> Bool {
            let length = (marker as NSString).length
            func has(_ text: String, at location: Int) -> Bool {
                location >= 0 && location + length <= string.length
                    && string.substring(with: NSRange(location: location, length: length)) == text
            }
            return has(marker, at: location) && (length > 1 || !(has(marker, at: location - 1) || has(marker, at: location + 1)))
        }
        var range = text
        if isMarker(open, at: range.location - openLength) { range.location -= openLength; range.length += openLength }
        if isMarker(close, at: NSMaxRange(range)) { range.length += closeLength }
        let selected = string.substring(with: range)
        if selected.hasPrefix(open), selected.hasSuffix(close), range.length >= openLength + closeLength {
            let inner = (selected as NSString).substring(with: NSRange(location: openLength,
                                                                       length: range.length - openLength - closeLength))
            replace(range, with: inner, in: view)
            return NSRange(location: range.location, length: (inner as NSString).length)
        }
        replace(text, with: open + string.substring(with: text) + close, in: view)
        return NSRange(location: text.location + openLength, length: text.length)
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
