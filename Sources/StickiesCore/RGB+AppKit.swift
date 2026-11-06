import AppKit

extension RGB {
    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Quantised to 8 bits so it round-trips through `#RRGGBB`.
    public init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let rgb = RGB(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        self = RGB(hex: rgb.hex) ?? rgb
    }
}
