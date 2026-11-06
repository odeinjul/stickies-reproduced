import Foundation

/// An sRGB colour with components in 0...1. Encoded as `#RRGGBB`.
public struct RGB: Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let black = RGB(0, 0, 0)

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB`; the `#` is optional.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(Double((value >> 16) & 0xFF) / 255,
                  Double((value >> 8) & 0xFF) / 255,
                  Double(value & 0xFF) / 255)
    }

    public var hex: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Linear mix: `fraction` 0 keeps `self`, 1 gives `other`.
    public func mixed(with other: RGB, _ fraction: Double) -> RGB {
        RGB(red + (other.red - red) * fraction,
            green + (other.green - green) * fraction,
            blue + (other.blue - blue) * fraction)
    }
}

extension RGB: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = RGB(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad colour \(string)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// The four shades a note is drawn with.
public struct NoteShades: Equatable {
    public let body: RGB
    public let spine: RGB
    public let control: RGB
    public let highlight: RGB

    init(_ body: String, _ spine: String, _ control: String, _ highlight: String) {
        self.body = RGB(hex: body)!
        self.spine = RGB(hex: spine)!
        self.control = RGB(hex: control)!
        self.highlight = RGB(hex: highlight)!
    }

    /// Shades for a custom body colour: progressively darker mixes toward black.
    public init(custom body: RGB) {
        self.body = body
        spine = body.mixed(with: .black, 0.08)
        control = body.mixed(with: .black, 0.25)
        highlight = body.mixed(with: .black, 0.35)
    }

    /// The bar inside the Collapse glyph: half control, half body.
    public var collapseBar: RGB { control.mixed(with: body, 0.5) }
}

/// Stickies' Colour menu. Yellow and grey are Stickies' exact values; blue, green,
/// pink and purple match their brightness in cleaner hues. Shades are body, bar
/// (spine), button outline (control) and pressed (highlight).
public enum NotePreset: String, CaseIterable, Codable {
    case yellow, blue, green, pink, purple, gray

    public var title: String { rawValue.capitalized }

    public var shades: NoteShades {
        switch self {
        case .yellow: return NoteShades("#FEF49C", "#FEEA3D", "#DBC503", "#BCA902")
        case .blue: return NoteShades("#CDE6FF", "#A9D2FC", "#4D9BE6", "#3A84CC")
        case .green: return NoteShades("#D4F5C4", "#B6EAA0", "#5DB84A", "#4A9C3A")
        case .pink: return NoteShades("#FFD6DC", "#FFBAC5", "#EF7A8E", "#D4637A")
        case .purple: return NoteShades("#E3D6FF", "#CDB8FA", "#9A78E0", "#8261C7")
        case .gray: return NoteShades("#EEEEEE", "#DADADA", "#A8A8A8", "#9E9E9E")
        }
    }
}

/// The Color menu keeps up to this many saved colours, on ⌘7, ⌘8, ⌘9 and ⌘0.
public let maxCustomColors = 4

/// A note's colour: a preset, or a custom body colour from the colour panel.
/// Encoded as the preset name (`"yellow"`) or `#RRGGBB`.
public enum NoteColor: Equatable {
    case preset(NotePreset)
    case custom(RGB)

    public var shades: NoteShades {
        switch self {
        case .preset(let preset): return preset.shades
        case .custom(let body): return NoteShades(custom: body)
        }
    }

    /// Folder name used when exporting to Notes.
    public var folderName: String {
        switch self {
        case .preset(let preset): return preset.title
        case .custom: return "Custom"
        }
    }
}

extension NoteColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let preset = NotePreset(rawValue: string) {
            self = .preset(preset)
        } else if let rgb = RGB(hex: string) {
            self = .custom(rgb)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown note colour \(string)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .preset(let preset): try container.encode(preset.rawValue)
        case .custom(let rgb): try container.encode(rgb.hex)
        }
    }
}
