# AGENTS.md

Stickies MD is a native macOS Stickies with Markdown notes: Swift and AppKit, no dependencies.

- `Sources/StickiesCore`: notes, Markdown rendering and editing, storage. Covered by tests.
- `Sources/StickiesMD`: the AppKit app (windows, menus, panels).
- `docs/SPEC.md`: how the app matches Stickies. Match Stickies unless the spec says otherwise; notes stay plain Markdown (no rich text, no pictures).

Run `make test` before every commit. `make run` builds and opens the app; `make snapshot` renders sample notes to `build/snapshots` for checking the look without opening windows.

## Releasing a version

1. Update the docs first: `docs/SPEC.md` for anything that changed, `README.md` if users will notice.
2. Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) and `Makefile` (`VERSION`).
3. `make test`, then `make docs` if the look changed, then `make release` (two zips in `build/`).
4. Commit, tag `vX.Y.Z`, push both, and run `gh release create vX.Y.Z build/StickiesMD-X.Y.Z-*.zip`.
5. Publishing the release updates the website's version and download links (`.github/workflows/site.yml`).
