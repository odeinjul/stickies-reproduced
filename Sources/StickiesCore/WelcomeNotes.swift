import CoreGraphics
import Foundation

/// The two notes shown the first time the app runs, placed like Stickies' own
/// welcome notes (from its saved state): a blue one behind, a yellow one in front,
/// overlapping at the top-left of the screen.
public enum WelcomeNotes {
    static let front = """
        # Make a note of it!
        MD Stickies keeps notes on your desktop, written in **Markdown**.

        - [ ] Click a box to tick it
        - Double-click the bar to collapse a note
        - Click the square at the top-left to close it

        Your notes come back each time you open MD Stickies.
        """

    static let back = """
        # Write in Markdown
        Formatting shows as you type; the markers appear on the line you're editing.

        - **bold**, *italic*, ~~strike~~ and `code`
        - Option-Tab starts a list, Tab nests it
        - Export as Markdown, text, RTF or to Notes

        > Float on Top and Translucent are in the Window menu.
        """

    /// Back to front, so the yellow note opens on top.
    public static func make(defaults: NoteDefaults, visible: CGRect) -> [Note] {
        var back = Note(defaults: defaults,
                        frame: CGRect(x: visible.minX + 48, y: visible.maxY - 40 - 268, width: 355, height: 268),
                        text: Self.back)
        back.color = .preset(.blue)
        var front = Note(defaults: defaults,
                         frame: CGRect(x: visible.minX + 69, y: visible.maxY - 62 - 260, width: 352, height: 260),
                         text: Self.front)
        front.color = .preset(.yellow)
        return [back, front]
    }
}
