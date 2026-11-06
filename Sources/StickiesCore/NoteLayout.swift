import CoreGraphics

/// Geometry measured from Stickies' `SNDocument.nib` and screenshots.
/// Points, origin at the bottom-left (AppKit's default).
public enum NoteLayout {
    public static let spineHeight: CGFloat = 12
    public static let buttonSize: CGFloat = 8
    public static let buttonY: CGFloat = 2
    public static let closeX: CGFloat = 12
    /// Zoom and Collapse are pinned to the right edge.
    public static let zoomInset: CGFloat = 32
    public static let collapseInset: CGFloat = 20
    public static let titleX: CGFloat = 24
    public static let titleRightInset: CGFloat = 36
    public static let growSize: CGFloat = 12
    public static let minSize = CGSize(width: 30, height: 30)
    public static let translucentAlpha: CGFloat = 0.75

    // Button frames are in spine coordinates.

    public static func closeFrame(width: CGFloat) -> CGRect {
        CGRect(x: closeX, y: buttonY, width: buttonSize, height: buttonSize)
    }

    public static func zoomFrame(width: CGFloat) -> CGRect {
        CGRect(x: width - zoomInset, y: buttonY, width: buttonSize, height: buttonSize)
    }

    public static func collapseFrame(width: CGFloat) -> CGRect {
        CGRect(x: width - collapseInset, y: buttonY, width: buttonSize, height: buttonSize)
    }

    public static func titleFrame(width: CGFloat) -> CGRect {
        CGRect(x: titleX, y: 0, width: max(0, width - titleRightInset - titleX), height: spineHeight)
    }

    /// The resize sign, in note coordinates: line d runs (W−2−d, 2) → (W−2, 2+d).
    public static func resizeLines(width: CGFloat) -> [(start: CGPoint, end: CGPoint)] {
        [8, 5, 2].map { d in
            (CGPoint(x: width - 2 - d, y: 2), CGPoint(x: width - 2, y: 2 + d))
        }
    }

    /// A collapsed note keeps its top edge and shrinks to the spine.
    public static func collapsedFrame(from frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - spineHeight, width: frame.width, height: spineHeight)
    }

    /// Expanding keeps the top edge and restores `height`.
    public static func expandedFrame(from frame: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    // MARK: Resizing from any edge

    /// Invisible resize strips along the sides and bottom; the top one is thinner
    /// so it stays clear of the bar's buttons.
    public static let edgeThickness: CGFloat = 3
    public static let topEdgeThickness: CGFloat = 2
    /// Near a corner, a strip also moves the neighbouring edge.
    public static let cornerSize: CGFloat = 10

    /// The frame after dragging `edges` by (dx, dy); opposite edges stay put.
    public static func resized(_ start: CGRect, edges: ResizeEdges, dx: CGFloat, dy: CGFloat) -> CGRect {
        var frame = start
        if edges.contains(.left) {
            frame.size.width = max(minSize.width, start.width - dx)
            frame.origin.x = start.maxX - frame.width
        } else if edges.contains(.right) {
            frame.size.width = max(minSize.width, start.width + dx)
        }
        if edges.contains(.bottom) {
            frame.size.height = max(minSize.height, start.height - dy)
            frame.origin.y = start.maxY - frame.height
        } else if edges.contains(.top) {
            frame.size.height = max(minSize.height, start.height + dy)
        }
        return frame
    }

    // MARK: Arrange By (measured from Stickies' code)

    /// Collapsed bars stack from 8 pt in and 16 pt down at the top-left of the
    /// screen, each directly under the last. Once a bar's bottom would fall below
    /// y = 100, a new column starts 200 pt to the right.
    public static func arrangedFrames(widths: [CGFloat], in visible: CGRect) -> [CGRect] {
        let top = visible.maxY - 16
        var origin = CGPoint(x: visible.minX + 8, y: top)
        var frames: [CGRect] = []
        for width in widths {
            frames.append(CGRect(x: origin.x, y: origin.y, width: width, height: spineHeight))
            origin.y -= spineHeight
            if origin.y < 100 { origin = CGPoint(x: origin.x + 200, y: top) }
        }
        return frames
    }
}

/// Which edges a resize drag moves.
public struct ResizeEdges: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1)
    public static let right = ResizeEdges(rawValue: 2)
    public static let top = ResizeEdges(rawValue: 4)
    public static let bottom = ResizeEdges(rawValue: 8)
}
