import AppKit

public extension NSAttributedString.Key {
    /// Markdown markers drawn invisibly, on lines that aren't being edited.
    static let markdownHidden = NSAttributedString.Key("StickiesMarkdownHidden")
    /// What `MarkdownLayoutManager` draws in place of a hidden block marker.
    static let markdownDecoration = NSAttributedString.Key("StickiesMarkdownDecoration")
}

public enum MarkdownDecoration: String {
    case bullet, unchecked, checked, quote, rule
}

/// A note's look: its font (and black text), and the styles derived from them.
public struct MarkdownStyle {
    public var font: NSFont
    public var textColor: NSColor

    public static let headingScales: [CGFloat] = [1.8, 1.45, 1.2, 1.1, 1.0, 1.0]
    /// Indent per list level; bullets and checkboxes sit in the gutter before it.
    public static let indent: CGFloat = 18

    public init(font: NSFont, textColor: NSColor = .black) {
        self.font = font
        self.textColor = textColor
    }

    func heading(_ level: Int) -> NSFont {
        let size = font.pointSize * Self.headingScales[min(max(level, 1), 6) - 1]
        return NSFontManager.shared.convert(NSFont(descriptor: font.fontDescriptor, size: size) ?? font,
                                            toHaveTrait: .boldFontMask)
    }

    var code: NSFont { NSFont.userFixedPitchFont(ofSize: font.pointSize * 0.95) ?? font }
    var markerColor: NSColor { textColor.withAlphaComponent(0.35) }
    var dimColor: NSColor { textColor.withAlphaComponent(0.55) }
    var codeBackground: NSColor { NSColor.black.withAlphaComponent(0.06) }
    var hiddenFont: NSFont { NSFont.systemFont(ofSize: 0.01) }
}

extension Note {
    public var markdownStyle: MarkdownStyle {
        MarkdownStyle(font: NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize))
    }
}

/// Typora-style rendering: the text stays Markdown and is styled in place.
/// Lines touching `editing` (the selection) show their markers, dimmed; every
/// other line hides them, and lists, checkboxes, quotes and rules are drawn
/// by `MarkdownLayoutManager` instead.
public enum MarkdownRenderer {
    static let fence = regex(#"^[ \t]*```"#)
    static let rule = regex(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    static let heading = regex(#"^(#{1,6})[ \t]+"#)
    static let task = regex(#"^([ \t]*)([-*+][ \t]+\[([ xX])\][ \t]+)"#)
    static let bullet = regex(#"^([ \t]*)([-*+][ \t]+)"#)
    static let ordered = regex(#"^([ \t]*)(\d+[.)][ \t]+)"#)
    static let quote = regex(#"^>[ \t]?"#)
    static let codeSpan = regex(#"(`+)(.+?)(\1)"#)
    static let link = regex(#"(\[)([^\]\n]+)(\]\([^)\s]+\))"#)
    static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#)
    static let italicStar = regex(#"(?<![*\w])(\*)(?![\s*])(.+?)(?<![\s*])(\*)(?![*\w])"#)
    static let italicUnderscore = regex(#"(?<![_\w])(_)(?![\s_])(.+?)(?<![\s_])(_)(?![_\w])"#)
    static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
    static let underline = regex(#"(<u>)(.+?)(</u>)"#)

    static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    static let fenceLines = try! NSRegularExpression(pattern: #"^[ \t]*```"#, options: .anchorsMatchLines)

    /// Code fences open or close; when their count changes, everything after them restyles.
    public static func fenceCount(in text: String) -> Int {
        guard hasFence(text) else { return 0 }
        return fenceLines.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Foundation's search: Swift's `String.contains` walks characters and costs
    /// milliseconds on a long note.
    static func hasFence(_ text: String) -> Bool { (text as NSString).range(of: "```").location != NSNotFound }

    /// Restyles the whole text, or just the lines touching `lines` (typing restyles
    /// only the edited lines; moving the cursor only the lines it leaves and enters).
    public static func render(_ storage: NSTextStorage, style: MarkdownStyle, editing: NSRange?,
                              lines: NSRange? = nil) {
        let text = storage.string
        let string = text as NSString
        var range = NSRange(location: 0, length: string.length)
        var inFence = false
        if let lines {
            let start = string.lineRange(for: NSRange(location: min(lines.location, string.length), length: 0))
            let end = string.lineRange(for: NSRange(location: min(NSMaxRange(lines), string.length), length: 0))
            range = NSUnionRange(start, end)
            if hasFence(text) {
                inFence = fenceLines.numberOfMatches(in: text, range: NSRange(location: 0, length: range.location)) % 2 == 1
            }
        }
        storage.beginEditing()
        storage.setAttributes([.font: style.font, .foregroundColor: style.textColor,
                               .paragraphStyle: NSParagraphStyle.default], range: range)
        var location = range.location
        while location < NSMaxRange(range) {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            var content = lineRange
            while content.length > 0, [10, 13].contains(string.character(at: NSMaxRange(content) - 1)) {
                content.length -= 1
            }
            let line = Line(storage: storage, string: text, range: content, paragraph: lineRange, style: style,
                            isEditing: editing.map { touches($0, lineRange, content) } ?? false)
            if line.starts(with: "`"), fence.firstMatch(in: text, range: content) != nil {
                line.renderCode(isFence: true)
                inFence.toggle()
            } else if inFence {
                line.renderCode(isFence: false)
            } else {
                line.renderBlock()
            }
            location = NSMaxRange(lineRange)
        }
        storage.endEditing()
    }

    static func touches(_ editing: NSRange, _ line: NSRange, _ content: NSRange) -> Bool {
        if editing.length == 0 { return editing.location >= line.location && editing.location <= NSMaxRange(content) }
        return NSIntersectionRange(editing, line).length > 0
    }

    /// The note as formatted text with the markers gone: for print, RTF and Notes.
    public static func rendered(_ markdown: String, style: MarkdownStyle) -> NSAttributedString {
        let storage = NSTextStorage(string: markdown)
        render(storage, style: style, editing: nil)
        let result = NSMutableAttributedString(attributedString: storage)
        // Runs split where the decoration changes, so "\t" + "- " keeps its bullet.
        var hidden: [(range: NSRange, decoration: MarkdownDecoration?)] = []
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
            guard attributes[.markdownHidden] != nil else { return }
            hidden.append((range, (attributes[.markdownDecoration] as? String).flatMap(MarkdownDecoration.init(rawValue:))))
        }
        for (range, decoration) in hidden.reversed() {
            let replacement: String
            switch decoration {
            case .bullet: replacement = "• "
            case .unchecked: replacement = "☐ "
            case .checked: replacement = "☑ "
            case .rule: replacement = "———"
            case .quote, nil: replacement = ""
            }
            var attributes = NSMaxRange(range) < result.length
                ? result.attributes(at: NSMaxRange(range), effectiveRange: nil)
                : [.font: style.font, .foregroundColor: style.textColor]
            if decoration == .rule { attributes[.foregroundColor] = style.dimColor }
            result.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        let all = NSRange(location: 0, length: result.length)
        result.removeAttribute(.markdownHidden, range: all)
        result.removeAttribute(.markdownDecoration, range: all)
        return result
    }

    /// One line of the note being styled.
    struct Line {
        let storage: NSTextStorage
        /// The whole text, taken once per render.
        let string: String
        let range: NSRange
        let paragraph: NSRange
        let style: MarkdownStyle
        let isEditing: Bool

        /// The first non-blank character is one of `characters`: a cheap check
        /// before running patterns, as most lines are plain text.
        func starts(with characters: String) -> Bool {
            let text = string as NSString
            var index = range.location
            while index < NSMaxRange(range), [9, 32].contains(text.character(at: index)) { index += 1 }
            guard index < NSMaxRange(range), let scalar = UnicodeScalar(text.character(at: index)) else { return false }
            return characters.unicodeScalars.contains(scalar)
        }

        func contains(anyOf characters: String) -> Bool {
            (string as NSString).rangeOfCharacter(from: CharacterSet(charactersIn: characters), range: range).location
                != NSNotFound
        }

        func renderCode(isFence: Bool) {
            guard range.length > 0 else { return }
            storage.addAttribute(.font, value: style.code, range: range)
            storage.addAttribute(isFence ? .foregroundColor : .backgroundColor,
                                 value: isFence ? style.markerColor : style.codeBackground, range: range)
        }

        func renderBlock() {
            guard range.length > 0 else { return }
            var inline = range
            guard starts(with: "#-*+_>0123456789") else { return renderInline(inline) }
            if MarkdownRenderer.rule.firstMatch(in: string, range: range) != nil {
                if isEditing {
                    storage.addAttribute(.foregroundColor, value: style.markerColor, range: range)
                } else {
                    // Keep the font so the line keeps its height; the layout manager draws the rule.
                    storage.addAttributes([.foregroundColor: NSColor.clear, .markdownHidden: true,
                                           .markdownDecoration: MarkdownDecoration.rule.rawValue], range: range)
                }
                return
            }
            if let match = MarkdownRenderer.heading.firstMatch(in: string, range: range) {
                let level = match.range(at: 1).length
                inline = after(match.range)
                if inline.length > 0 { storage.addAttribute(.font, value: style.heading(level), range: inline) }
                marker(match.range, decoration: nil)
            } else if let match = MarkdownRenderer.task.firstMatch(in: string, range: range) {
                let checked = (string as NSString).substring(with: match.range(at: 3)) != " "
                list(match, decoration: checked ? .checked : .unchecked)
                inline = after(match.range)
                if checked, inline.length > 0 { storage.addAttribute(.foregroundColor, value: style.dimColor, range: inline) }
            } else if let match = MarkdownRenderer.bullet.firstMatch(in: string, range: range) {
                list(match, decoration: .bullet)
                inline = after(match.range)
            } else if let match = MarkdownRenderer.ordered.firstMatch(in: string, range: range) {
                // Numbers stay visible; only the nesting whitespace hides.
                let level = MarkdownRenderer.level(of: (string as NSString).substring(with: match.range(at: 1)))
                let numberWidth = width(of: match.range(at: 2))
                paragraphIndent(first: MarkdownStyle.indent * CGFloat(level),
                                head: MarkdownStyle.indent * CGFloat(level) + numberWidth)
                hide(match.range(at: 1), decoration: nil)
                inline = after(match.range)
            } else if let match = MarkdownRenderer.quote.firstMatch(in: string, range: range) {
                paragraphIndent(first: MarkdownStyle.indent, head: MarkdownStyle.indent)
                marker(match.range, decoration: .quote)
                inline = after(match.range)
                if inline.length > 0 { storage.addAttribute(.foregroundColor, value: style.dimColor, range: inline) }
            }
            renderInline(inline)
        }

        /// Bullets and checkboxes: content starts at the list indent, the marker
        /// (or its drawn replacement) sits in the gutter just before it. The gutter
        /// fits the whole marker, so the text doesn't move when the line is edited.
        func list(_ match: NSTextCheckingResult, decoration: MarkdownDecoration) {
            let level = MarkdownRenderer.level(of: (string as NSString).substring(with: match.range(at: 1)))
            let markerWidth = width(of: match.range(at: 2))
            // "[x]" is wider than "[ ]": size the gutter for the wider one so ticked
            // and unticked items line up.
            let markerText = (string as NSString).substring(with: match.range(at: 2))
            let gutter = decoration == .bullet ? markerWidth
                : (markerText.replacingOccurrences(of: "[ ]", with: "[x]") as NSString)
                    .size(withAttributes: [.font: style.font]).width
            let indent = MarkdownStyle.indent * CGFloat(level) + max(MarkdownStyle.indent, ceil(gutter))
            let first = isEditing ? indent - markerWidth : indent
            paragraphIndent(first: first, head: indent)
            hide(match.range(at: 1), decoration: nil)
            marker(match.range(at: 2), decoration: decoration)
        }

        func renderInline(_ range: NSRange) {
            guard range.length > 0, contains(anyOf: "*_~`<[") else { return }
            var taken: [NSRange] = []
            func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

            for match in MarkdownRenderer.codeSpan.matches(in: string, range: range) {
                storage.addAttributes([.font: style.code, .backgroundColor: style.codeBackground], range: match.range(at: 2))
                marker(match.range(at: 1), decoration: nil)
                marker(match.range(at: 3), decoration: nil)
                taken.append(match.range)
            }
            for match in MarkdownRenderer.link.matches(in: string, range: range) where free(match.range) {
                storage.addAttributes([.foregroundColor: NSColor.linkColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue], range: match.range(at: 2))
                marker(match.range(at: 1), decoration: nil)
                marker(match.range(at: 3), decoration: nil)
            }
            let spans: [(NSRegularExpression, (NSRange) -> Void)] = [
                (MarkdownRenderer.bold, { self.convert($0, trait: .boldFontMask) }),
                (MarkdownRenderer.italicStar, { self.convert($0, trait: .italicFontMask) }),
                (MarkdownRenderer.italicUnderscore, { self.convert($0, trait: .italicFontMask) }),
                (MarkdownRenderer.strike, {
                    self.storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: $0)
                }),
                (MarkdownRenderer.underline, {
                    self.storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: $0)
                }),
            ]
            for (pattern, apply) in spans {
                for match in pattern.matches(in: string, range: range) where free(match.range) {
                    apply(match.range(at: 2))
                    marker(match.range(at: 1), decoration: nil)
                    marker(match.range(at: 3), decoration: nil)
                }
            }
        }

        // MARK: Helpers

        func after(_ marker: NSRange) -> NSRange {
            NSRange(location: NSMaxRange(marker), length: NSMaxRange(range) - NSMaxRange(marker))
        }

        /// Dimmed while editing the line, hidden otherwise.
        func marker(_ range: NSRange, decoration: MarkdownDecoration?) {
            guard range.length > 0 else { return }
            if isEditing {
                storage.addAttribute(.foregroundColor, value: style.markerColor, range: range)
            } else {
                hide(range, decoration: decoration)
            }
        }

        func hide(_ range: NSRange, decoration: MarkdownDecoration?) {
            guard range.length > 0 else { return }
            storage.addAttributes([.font: style.hiddenFont, .foregroundColor: NSColor.clear, .markdownHidden: true],
                                  range: range)
            if let decoration { storage.addAttribute(.markdownDecoration, value: decoration.rawValue, range: range) }
        }

        func convert(_ range: NSRange, trait: NSFontTraitMask) {
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                guard let font = value as? NSFont else { return }
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
            }
        }

        func paragraphIndent(first: CGFloat, head: CGFloat) {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = first
            paragraphStyle.headIndent = head
            // Hidden nesting tabs would still jump to a tab stop; the indent does the nesting.
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = 0.01
            storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraph)
        }

        func width(of range: NSRange) -> CGFloat {
            ((string as NSString).substring(with: range) as NSString).size(withAttributes: [.font: style.font]).width
        }
    }

    /// Nesting level from leading whitespace: a tab or two spaces per level.
    static func level(of whitespace: String) -> Int {
        let tabs = whitespace.filter { $0 == "\t" }.count
        let spaces = whitespace.filter { $0 == " " }.count
        return tabs + spaces / 2
    }
}

/// Draws what hidden block markers stand for: bullets, checkboxes, quote bars, rules.
public final class MarkdownLayoutManager: NSLayoutManager {
    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.markdownDecoration, in: characters) { value, range, _ in
            guard let raw = value as? String, let decoration = MarkdownDecoration(rawValue: raw) else { return }
            draw(decoration, markerRange: range, storage: storage, origin: origin)
        }
    }

    private func draw(_ decoration: MarkdownDecoration, markerRange: NSRange, storage: NSTextStorage, origin: NSPoint) {
        let markerGlyph = glyphIndexForCharacter(at: markerRange.location)
        let line = lineFragmentRect(forGlyphAt: markerGlyph, effectiveRange: nil)
        let paragraph = storage.attribute(.paragraphStyle, at: markerRange.location, effectiveRange: nil) as? NSParagraphStyle
        let contentIndex = min(NSMaxRange(markerRange), storage.length - 1)
        let font = (storage.attribute(.font, at: contentIndex, effectiveRange: nil) as? NSFont)
            .flatMap { $0.pointSize < 1 ? nil : $0 } ?? NSFont.systemFont(ofSize: 12)
        let color = (storage.attribute(.foregroundColor, at: contentIndex, effectiveRange: nil) as? NSColor)
            .flatMap { $0.alphaComponent == 0 ? nil : $0 } ?? .textColor
        let baseline = origin.y + line.minY + location(forGlyphAt: glyphIndexForCharacter(at: contentIndex)).y
        let gutter = origin.x + line.minX + (paragraph?.headIndent ?? MarkdownStyle.indent)
        // Where the marker's text would start if shown: drawn shapes sit exactly
        // where the "-" or "[ ]" is while the line is being edited.
        let marker = (storage.string as NSString).substring(with: markerRange)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let markerStart = gutter - width(marker)
        let midY = baseline - font.capHeight / 2

        switch decoration {
        case .bullet:
            let diameter = max(4, (font.pointSize * 0.36).rounded())
            let centerX = markerStart + width(String(marker.prefix(1))) / 2
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: centerX - diameter / 2, y: midY - diameter / 2,
                                        width: diameter, height: diameter)).fill()
        case .unchecked, .checked:
            let size = ceil(font.capHeight * 1.3)
            // Measure as "[x]" (the wider form, which sets the gutter) so ticked and unticked boxes line up.
            let shape = marker.replacingOccurrences(of: "[ ]", with: "[x]")
            let open = shape.firstIndex(of: "[") ?? shape.startIndex
            let close = shape.firstIndex(of: "]").map { shape.index(after: $0) } ?? shape.endIndex
            let centerX = gutter - width(shape) + width(String(shape[..<open])) + width(String(shape[open..<close])) / 2
            let box = NSRect(x: (centerX - size / 2).rounded(), y: (midY - size / 2).rounded(), width: size, height: size)
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            if decoration == .checked {
                color.setFill()
                outline.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: box.minX + size * 0.24, y: box.minY + size * 0.52))
                tick.line(to: NSPoint(x: box.minX + size * 0.43, y: box.minY + size * 0.72))
                tick.line(to: NSPoint(x: box.minX + size * 0.77, y: box.minY + size * 0.30))
                tick.lineWidth = max(1.5, size * 0.13)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                color.withAlphaComponent(0.7).setStroke()
                outline.stroke()
            }
        case .quote:
            color.withAlphaComponent(0.35).setFill()
            let paragraphRange = (storage.string as NSString).paragraphRange(for: markerRange)
            let glyphs = glyphRange(forCharacterRange: paragraphRange, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                NSRect(x: origin.x + rect.minX + 4, y: origin.y + rect.minY, width: 3, height: rect.height).fill()
            }
        case .rule:
            color.withAlphaComponent(0.4).setFill()
            NSRect(x: origin.x + line.minX, y: origin.y + line.midY, width: line.width, height: 1).fill()
        }
    }
}
