# MD Stickies — Spec

Repo: `~/Documents/Work/stickies-reproduced`. App: MD Stickies (`MD Stickies.app`, `local.stickies-md`; notes in `~/Library/Application Support/Stickies MD`).

Native macOS (Swift + AppKit) clone of Apple Stickies. Notes are Markdown, rendered Typora style: markers hidden except on the line being edited. No rich-text styling (text colours, kern, outline…).
Status: spec only, nothing built. Rule: **match native Stickies** wherever it has a behavior. Values marked *measured* come from Stickies' own nib (`SNDocument.nib`) and machine code.

## 1. What Apple Stickies does today (v10.3, macOS 15.5)

Taken from the app's own menu/strings tables and asset catalog.

| Area | Stickies feature | v1? |
|---|---|---|
| File | New Note, Close, Import Text…, Export Text… (RTFD / RTF / Plain Text), Export All to Notes…, Print… | ✅, plus Markdown in Export Text…; no pictures |
| Note bar | **Close** (left), **Zoom** + **Collapse** (right); double-click bar = collapse/expand | ✅ |
| Window | Float on Top, Translucent, Collapse, Zoom, Bring All to Front | ✅ |
| Window | Arrange By: Colour / Content / Date / Location on Screen, Undo/Redo Arrange | ✅ |
| Colour | Yellow, Blue, Green, Pink, Purple, Grey + Customize Color… | ✅ |
| Font | Show Fonts, Bold/Italic/Underline/Outline/Strikethrough, Bigger/Smaller, Kern/Ligature/Baseline, Show Colours, Copy/Paste Style, **Use as Default** | Partly: Bold / Italic / Underline / Strikethrough add Markdown markers; font and size for the whole note; text colours, Outline, Kern, Ligature, Baseline, Copy/Paste Style dropped (Markdown can't store them) |
| Edit | Find / Replace (current note or all notes), spelling, substitutions, speech | ✅ own Find panel; the rest via NSTextView |
| Defaults | Window 300×200, Helvetica 12, not floating, not translucent | ✅ same |

## 2. v1 requirements

1. **Borderless note window.** No system frame. Custom thin bar on top. Resizable, draggable by the bar.
2. **Text.** Markdown, saved as `<id>.md`, rendered Typora style. Notes autosave. Import/Export a single note as RTFD, RTF, Plain Text or Markdown (Format popup in the save panel, like Stickies). Notes hold no pictures.
3. **Float on Top** and **Translucent**, toggled per note (Window menu).
4. **Multiple notes.** Each is its own window; all are restored on relaunch.
5. **Three buttons in the bar:** Close (left), Zoom (right), Collapse (right), as in Stickies.
6. **Colours:** 6 Stickies presets + custom via the colour panel.
7. **Fonts and colours via the native panels.** The font and size apply to the whole note; there are no text colours (Markdown can't store per-character fonts or colours). "Use as Default" saves the current settings for new notes.
8. **Export All to Notes.**

## 3. Visual design

```
x: 0   12  20                      268 276 280 288  300
   ┌──────────────────────────────────────────────────┐ ─┐
   │    [□]                          [◢]   [⊟]        │  │ spine 12 pt, spine colour
   └──────────────────────────────────────────────────┘ ─┘ buttons 8×8 at y=2
   │ Text… (Helvetica 12)                             │
   │                                                  │  text area 300×188
   │                                               ⋰ │  (scroll view + text view); ⋰ = resize sign
   └──────────────────────────────────────────────────┘
     Close                          Zoom  Collapse
Collapsed = spine only (12 pt tall) + title text; resizing disabled.
```

### Layout (measured)

| Item | Value |
|---|---|
| Window | 300 × 200 default, min 30 × 30, class `SNWindow` |
| Spine (bar) | full width × **12 pt**, pinned to the top |
| Close | 8 × 8 pt at x = 12, y = 2. Glyph: empty square, 1 pt control-colour outline, body-colour fill |
| Zoom | 8 × 8 pt at x = width − 32 (pinned right). Glyph: right triangle ◢ (lower-right half), 1 pt control-colour outline with anti-aliased diagonal, body fill |
| Collapse | 8 × 8 pt at x = width − 20 (12 pt right margin, 4 pt gap). Glyph: the Close square plus a 2 pt horizontal bar at y = 4–5, coloured 50 % control + 50 % body (`#ECDC4E` on yellow) |
| Buttons | Custom-drawn cells, disabled in the nib; drawn only on the active (key) note |
| Pressed | While the mouse is down on a button, its glyph fill becomes the **highlight colour**; outline unchanged. No hover state |
| Active spine | Full-width 12 pt strip in the spine colour (screenshot: `#FEEA3C` ≈ `#FEEA3D`) |
| Resize sign | **Clone addition** (native draws nothing). Three 1 pt diagonal lines in the control colour, bottom-left → top-right, in an 8 × 8 pt box 2 pt from the right and bottom edges. With origin at the bottom-left of the note and width W, line *d* runs from (W − 2 − d, 2) to (W − 2, 2 + d) for d = 8, 5, 2. Drawn only on the active note; hidden when collapsed. Hit area 12 × 12 pt (a11y label "grow area") |
| **Inactive note** | No visible spine, no buttons, no resize corner: the whole window is the body colour (screenshot: exactly `#FEF49C`) |
| Frame | Square corners, 1 pt grey hairline + standard window shadow (`hasShadow = true`) (screenshot) |
| Title | Shown only when collapsed. Text = the note's first non-empty line, trimmed; "Untitled" if the note is empty. System font **9 pt**, natural alignment, truncated at the tail with "…" (*measured* from the nib), black. Runs from x = 24 to W − 36 so it never overlaps the buttons |
| Text area | Scroll view + text view, 300 × 188; first glyph ≈ 11 pt from the left edge (screenshot) → `textContainerInset.width` ≈ 5 + default 5 pt line padding |

### Palette

Yellow and grey are Stickies' exact values (table below). Blue, green, pink and purple match yellow's brightness in cleaner hues (Stickies' are cyan, lime and periwinkle):

| Colour | Body | Spine | Control | Highlight |
|---|---|---|---|---|
| Blue | `#CDE6FF` | `#A9D2FC` | `#4D9BE6` | `#3A84CC` |
| Green | `#D4F5C4` | `#B6EAA0` | `#5DB84A` | `#4A9C3A` |
| Pink | `#FFD6DC` | `#FFBAC5` | `#EF7A8E` | `#D4637A` |
| Purple | `#E3D6FF` | `#CDB8FA` | `#9A78E0` | `#8261C7` |

App icon (`scripts/make-icon.swift`, `make icon`), following Apple's macOS icon layout: one continuous-corner shape (superellipse, n = 5) on the 824 pt grid of a 1024 canvas, the standard drop shadow (10 down, 10 blur, 30% black) and no other shadows or effects. Inside, after Stickies' own but in soft blue: a `#D6EAFF` sheet whose pad shows as two bands along the bottom (`#B4D6FA`, `#8DBAEA`), and a squiggle, a full line and a short line in `#93BFEC`.

Stickies' own palette (exact sRGB from its asset catalog); the clone keeps its yellow and grey:

| Colour | Body | Spine (bar) | Control (buttons) | Highlight (pressed) |
|---|---|---|---|---|
| Yellow (default) | `#FEF49C` | `#FEEA3D` | `#DBC503` | `#BCA902` |
| Blue | `#ADF4FF` | `#89F0FF` | `#24D0E9` | `#02BCD7` |
| Green | `#B2FFA1` | `#83FE83` | `#51BB51` | `#48A248` |
| Pink | `#FFC7C7` | `#FFB2B2` | `#F87F7F` | `#E27575` |
| Purple | `#B6CAFF` | `#9BB6FE` | `#7D9BEB` | `#7591DC` |
| Grey | `#EEEEEE` | `#DADADA` | `#A8A8A8` | `#9E9E9E` |
| White (in assets, not in menu) | `#FFFFFF` | `#7F7F7F` | `#FFFFFF` | `#FFFFFF` |

Custom colour: spine, control and highlight are the body colour mixed 8 %, 25 % and 35 % toward black.

## 4. Native frameworks and APIs

Stickies itself links only **AppKit, Foundation, CoreServices, QuartzCore, UniformTypeIdentifiers**. It has no entitlements. v1 needs nothing else.

| Feature | API | Notes |
|---|---|---|
| Borderless window | `NSWindow` subclass, `styleMask = [.closable, .miniaturizable, .resizable]` (no `.titled`) | *Measured*: Stickies' mask is 14 = exactly these. Override `canBecomeKey`/`canBecomeMain` → `true` (untitled windows refuse key by default) |
| Window behavior | `collectionBehavior = [.stationary, .fullScreenNone]`, `animationBehavior = .none`, `tabbingMode = .disallowed`, `isRestorable = true` | *Measured* (528 / 2 / 2). Notes stay on the Space they were made on and don't slide away in Mission Control |
| Bar + buttons | Custom `NSView` (Stickies: `SNSpineView`) + 3 custom-drawn `NSButton`s | Drag via `mouseDown`/`mouseDragged` (Stickies' way) or `window.performDrag(with:)`; double-click → collapse |
| Resize | Grip view in the bottom-right, plus invisible strips on every edge (3 pt; 2 pt on top to clear the buttons) that also take the neighbouring edge within 10 pt of a corner | Stickies' guide: "Drag the note's edge (top, bottom, or sides)". Hidden while collapsed |
| Note info | Bar tooltip "Created: …\nModified: …" | Stickies' own string; hover over the bar |
| Lists | Option-Tab (`insertTabIgnoringFieldEditor:`) starts a bulleted `NSTextList` | Return, Return twice, Tab and Shift-Tab are NSTextView's built-in list handling (tested) |
| Arrange By | Collapses every note and stacks the bars on the first screen: 8 pt in, 16 pt down, bars touching; new column 200 pt right once below y = 100 | *Measured* from Stickies' arrange code. Sorts by colour (menu order, custom last), content (case-insensitive), modification date (oldest first, assumed), position (top-down, then left-right). Undo/Redo Arrange ⌥⌘Z / ⌥⇧⌘Z |
| Find | Own panel: Find, Replace With, Current Note / All Notes, Ignore Case (on), Replace All / Replace / Replace & Find / Previous / Next; Edit → Find ▸ Find… ⌘F, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E, Jump to Selection ⌘J | Labels from Stickies' strings. All Notes continues into the next note and wraps |
| Float on Top | `window.level = .floating` / `.normal` | Same call Stickies uses (`setLevel:`); a floating Stickies note measured at window layer 3 = `.floating` |
| Translucent | `window.alphaValue = 0.75` / `1.0` | *Measured*: Stickies' constant table is `[0.75, 1.0]` |
| Collapse | `setFrame(_:display:animate:)` to 12 pt; remove `.resizable` from the mask while collapsed; show title | *Measured*: Stickies clears mask bit 8 (resizable) when collapsed |
| Close | Empty note → delete silently. Otherwise modal `NSAlert`: "Are you sure you want to discard this Stickies note?" / "If you don't save this note, its contents will be lost." Buttons **Save…** (→ export panel), **Cancel**, **Delete Note** | *Measured* flow (`isContentEmpty` → `deleteDocument`, else alert → `exportSticky:`) |
| Zoom | `window.setFrame(screen.visibleFrame, …)`; again restores the earlier frame | Observed: fills the screen but is not full screen mode. Collapsing a zoomed note leaves a full-width bar along the top |
| Text | `NSTextView` in `NSScrollView`, `isRichText = false` (the text is Markdown) on TextKit 1 with `MarkdownLayoutManager`; `MarkdownRenderer` restyles after every edit and when the selection moves to another line | Find, spelling and substitutions come for free |
| Font + weight | `NSFontManager` / `NSFontPanel` (`usesFontPanel = true`, ⌘T) | Applies to the whole note |
| Colours | `NSColorPanel` (`changeColor:`); colour presets in `Assets.xcassets` | One panel for text colour and Customize Color… |
| Defaults | `UserDefaults` (font archived with `NSKeyedArchiver`, as Stickies does) | Size, font, colour, floating, translucent |
| Import/Export Text | `NSSavePanel` + accessory "Format:" popup (RTFD, RTF, Plain Text, Markdown; last choice remembered); `NSOpenPanel` for all four | RTF/RTFD via `NSAttributedString` (`fileWrapper` for RTFD); Markdown via `MarkdownConverter`; pictures in imported RTFD are dropped; imported Markdown keeps its markers as typed |
| Storage | `FileManager` → `~/Library/Application Support/<App>/` | `notes/<uuid>.txt` + `notes.json` (frame, colour, font, flags) |
| Multiple notes | One `NSWindowController` per note + an `AppDelegate` registry | Stickies uses `NSDocument` (`SNDocument`, autosaves in place); a custom store is simpler for v1 |
| Export to Notes | `NSWorkspace.urlForApplication(withBundleIdentifier: "com.apple.Notes")` + open the exported files with Notes | Stickies writes the notes as files into a folder, then hands them to Notes (inferred from its strings). Fallback: AppleScript `make new note` (needs an Automation permission prompt) |
| Print | `NSPrintOperation` on an offscreen `NSTextView` the width of the page, with `NSPrintInfo` header and footer on | Observed: white page, note's font, header "Stickies" + date/time, footer "Page 1 of 1" |
| Menus | `NSMenu` in code | File / Edit / Font / Colour / Window |

### Export All to Notes (native flow, confirmed)

1. File → Export All to Notes… shows an alert: **"Export all Stickies to Notes?"**
   Informative text: "Your Stickies will appear in an “Imported Notes” folder in the Notes application. Text formatting, links and pictures will be preserved. Notes will be organized into separate folders based on color."
   Buttons: **Export All** / **Cancel**.
2. Notes gets an "Imported Notes" folder with one sub-folder per colour (Yellow, Blue, …).
3. A summary titled "Export From Stickies Summary" lists "Total notes exported: N" and "Date exported: …" (from Stickies' strings).

Clone: same alert and folder-per-colour layout. Formatted notes go as `.rtf`, so Notes keeps formatting and links (no pictures).

### Shortcuts

From Stickies' menus: ⌘N new · ⌘W close · ⌘P print · ⌘T fonts · ⇧⌘C colours · ⌘1–⌘6 colours (menu shows a swatch and a checkmark on the current one) · ⌘7–⌘0 up to four saved colours of your own: Color → New Color… saves the note's colour as a new slot and edits it live in the colour panel; Edit Color ▸ adjusts one (every note using it follows); Remove Color ▸ frees a slot (notes keep their colour) · ⌘M Collapse · ⇧⌘M Zoom · ⌥⌘F Float on Top · ⌥⌘T Translucent. Import/Export Text have no shortcut. "Use as Default" lives in the Window menu. The Window menu lists every note with its colour swatch.

The Fonts and Colors panels open beside the note being edited, top edges level, to its right if there's room (else its left), kept on screen. Font menu: Show Fonts ⌘T, Bold ⌘B (`**`), Italic ⌘I (`*`), Underline ⌘U (`<u>`), Strikethrough (`~~`) · Bigger ⌘+, Smaller ⌘−. With a selection they wrap or unwrap it; with none they insert a pair.

## 5. Later: basic Markdown (WYSIWYG)

All native options keep the file as plain `.md`/`.txt`. No WKWebView, unlike Jotdown.

| Option | How | Effort | Fit |
|---|---|---|---|
| **A. Live styling** (recommended first) | `NSTextStorage` delegate re-styles after each edit: `#` → larger bold, `**x**` → bold, markers dimmed | Low | Bear / iA Writer style, 100% TextKit |
| B. Hide markers + checkboxes | TextKit 2 (`NSTextLayoutManager`, custom `NSTextLayoutFragment`), `NSTextAttachment` for `- [ ]` | High | Obsidian-style live preview |
| Parser for A/B | Basic subset: regex. Fuller: Apple's `swift-markdown` (cmark-gfm, gives source ranges) | — | `AttributedString(markdown:)` (Foundation, macOS 12+) parses but gives no marker ranges, so it suits read-only rendering, not live editing |

**Built: Typora style (option B).** Bullets and checkboxes are drawn as shapes (a dot; a rounded square, filled with a white tick when ticked) centred where the `-` / `[ ]` sits while the line is edited. The gutter fits the `- [x] ` marker, so text doesn't move between editing and preview and ticked/unticked items line up. `NoteWindowController.livePreview = false` shows plain Markdown instead. The note's text is its Markdown. `MarkdownRenderer` styles it in place; on lines that aren't being edited the markers get a 0.01 pt clear font (`.markdownHidden`), and `MarkdownLayoutManager` draws what block markers stand for. The line(s) under the selection show their markers, dimmed. An unfocused note shows everything rendered.

| Markdown | Shown as |
|---|---|
| `# ` … `###### ` | bold heading, 1.8× / 1.45× / 1.2× / 1.1× / 1× / 1× the note font |
| `**x**` `__x__` `*x*` `_x_` `~~x~~` `` `x` `` `<u>x</u>` | bold, italic, strikethrough, monospaced on a tint, underline |
| `[text](url)` | link-coloured, underlined text |
| `- ` `* ` `+ ` (tab or 2 spaces per level) | drawn bullet, 18 pt indent per level |
| `- [ ] ` / `- [x] ` | drawn ☐ / ☑ (ticked items dimmed); click it to toggle |
| `1. ` | number stays visible, hanging indent |
| `> ` | bar on the left, dimmed text |
| `---` `***` `___` | a rule across the note |
| ```` ``` ```` fences | monospaced block, contents literal |

Editing: Return continues a list, checklist, numbered list or quote (twice ends it); Tab / Shift-Tab nest list lines; Option-Tab starts a list. Export Text…: Markdown as typed, Plain Text / RTF / RTFD as the note looks. Print and Export All to Notes use the rendered note. Older RTF notes convert to Markdown (`MarkdownConverter`) on first launch.

### First launch

Like Stickies, the first launch shows two welcome notes (own wording, in Markdown), placed from Stickies' saved state: a blue "Write in Markdown" note 355 × 268 at (48, top − 40) behind a yellow "Make a note of it!" note 352 × 260, 21 pt right and 22 pt lower. Once anything has been saved they never come back; deleting every note leaves one empty note.

### Limits

A note holds at most 100,000 characters (`NoteLimits.maxCharacters`, about 5,000 lines): typing past it beeps, a paste that doesn't fit is refused with an explanation, Import Text… cuts a longer file and says so. Deleting always works, so an over-long older note can be trimmed. At the cap typing restyles in under 7 ms; under 1,000 lines in about 0.2 ms.

## 6. Decisions (match native)

| Question | Decision | Basis |
|---|---|---|
| Minimize button | Collapses to the 12 pt bar, not the Dock | Stickies' button is "Collapse" (a11y label "minimise") |
| Close | Empty → delete; else Save… / Cancel / Delete Note | Measured flow above |
| Spaces | Current Space only, stationary | Collection behavior 528 |
| Translucency | Fixed 0.75 | Measured constant |
| Float on Top | Level 3 (`.floating`) | Measured; ⌥⌘F |
| Min macOS | 13 (Ventura) | Not a Stickies behavior (it ships with the OS); 13 keeps TextKit 2 available for later Markdown |

## 7. Deviations from native

- **Resize sign:** native Stickies draws no resize corner; the clone draws a 3-line grip on the active note.
- **Pressed look** and **collapsed title text** are simple choices, not measured (see Layout).

## Sources

- Stickies.app 10.3 on this Mac: `MainMenu.loctable`, `SNDocument.loctable`, `Assets.car`, binary symbols, `com.apple.Stickies` defaults
- [Stickies User Guide (Apple)](https://support.apple.com/en-ca/guide/stickies/welcome/10.3/mac/26)
- [WebNots: How to use Stickies](https://www.webnots.com/how-to-use-stickies-in-mac-like-a-pro/) (⌥⌘F)
