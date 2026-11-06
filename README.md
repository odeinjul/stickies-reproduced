<p align="center"><img src="docs/icon.png" width="128" alt="Stickies MD icon"></p>

# Stickies MD

Apple's Stickies, rebuilt natively for macOS, with notes written in Markdown.

![Stickies MD notes on a desktop](docs/preview.png)

**Does**
- Stickies' notes: six colours, float on top, translucent, collapse, zoom, arrange, find across notes
- Markdown, previewed as you type: headings, bold, italic, code, links, lists, checkboxes you can click
- Saves each note as a `.md` file; exports to Markdown, text, RTF or Apple Notes

**Doesn't**
- Rich text: no text colours or per-word fonts
- Pictures or attachments
- Sync between Macs

## Install

Download `StickiesMD-0.1.zip` from [Releases](https://github.com/odeinjul/stickies-reproduced/releases) and move the app to Applications. It isn't notarized, so the first time, right-click it and choose Open (or run `xattr -dr com.apple.quarantine /Applications/StickiesMD.app`). Needs macOS 13 or later.

To build it yourself: `make run` (Swift; Xcode for `make test`). How it matches Stickies: [docs/SPEC.md](docs/SPEC.md).

MIT licensed. Not affiliated with Apple.
