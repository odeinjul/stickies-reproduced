import Foundation

/// Window → Arrange By, in Stickies' order.
public enum ArrangeOrder: Int, CaseIterable {
    case color, content, date, location

    public var title: String {
        switch self {
        case .color: return "Color"
        case .content: return "Content"
        case .date: return "Date"
        case .location: return "Location on Screen"
        }
    }
}

public enum NoteArrange {
    /// Mirrors Stickies' compareColor:, compareContent:, compareModificationDate:
    /// and comparePosition:. Ties keep their current order.
    public static func sorted(_ notes: [Note], by order: ArrangeOrder) -> [Note] {
        notes.enumerated().sorted { a, b in
            switch compare(a.element, b.element, by: order) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.element)
    }

    static func compare(_ a: Note, _ b: Note, by order: ArrangeOrder) -> ComparisonResult {
        switch order {
        case .color:
            return compare(rank(a.color), rank(b.color))
        case .content:
            return a.text.localizedCaseInsensitiveCompare(b.text)
        case .date:
            return a.modified.compare(b.modified)
        case .location:
            // Top to bottom, then left to right.
            if a.frame.maxY != b.frame.maxY { return compare(b.frame.maxY, a.frame.maxY) }
            return compare(a.frame.minX, b.frame.minX)
        }
    }

    /// Colour menu order; custom colours last.
    static func rank(_ color: NoteColor) -> Int {
        if case .preset(let preset) = color, let index = NotePreset.allCases.firstIndex(of: preset) { return index }
        return NotePreset.allCases.count
    }

    static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }
}
