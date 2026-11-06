import Foundation

/// Matching for the Find panel, within one note or across all notes.
public enum TextSearch {
    public static func options(ignoreCase: Bool) -> NSString.CompareOptions {
        ignoreCase ? [.caseInsensitive] : []
    }

    /// The first match after `location` (forward) or before it (backward),
    /// wrapping around the text when `wraps` is set.
    public static func match(of query: String, in text: String, from location: Int,
                             forward: Bool, ignoreCase: Bool, wraps: Bool) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let string = text as NSString
        let location = min(max(location, 0), string.length)
        var options = options(ignoreCase: ignoreCase)
        if !forward { options.insert(.backwards) }
        let first = forward
            ? NSRange(location: location, length: string.length - location)
            : NSRange(location: 0, length: location)
        let found = string.range(of: query, options: options, range: first)
        if found.location != NSNotFound { return found }
        guard wraps else { return nil }
        let wrapped = string.range(of: query, options: options, range: NSRange(location: 0, length: string.length))
        return wrapped.location == NSNotFound ? nil : wrapped
    }

    /// Every non-overlapping match, for Replace All.
    public static func ranges(of query: String, in text: String, ignoreCase: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let string = text as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < string.length {
            let found = string.range(of: query, options: options(ignoreCase: ignoreCase),
                                     range: NSRange(location: location, length: string.length - location))
            if found.location == NSNotFound { break }
            ranges.append(found)
            location = NSMaxRange(found)
        }
        return ranges
    }

    /// Across notes: continues from `location` in note `start`, then through the
    /// following (or previous) notes, finally wrapping back into `start`.
    public static func match(of query: String, in texts: [String], note start: Int, from location: Int,
                             forward: Bool, ignoreCase: Bool) -> (note: Int, range: NSRange)? {
        guard texts.indices.contains(start) else { return nil }
        if let range = match(of: query, in: texts[start], from: location, forward: forward,
                             ignoreCase: ignoreCase, wraps: false) {
            return (start, range)
        }
        let count = texts.count
        for step in 1...count {
            let index = ((start + (forward ? step : -step)) % count + count) % count
            let from = forward ? 0 : (texts[index] as NSString).length
            if let range = match(of: query, in: texts[index], from: from, forward: forward,
                                 ignoreCase: ignoreCase, wraps: false) {
                return (index, range)
            }
        }
        return nil
    }
}
