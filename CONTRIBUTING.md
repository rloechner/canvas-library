# Contributing to Canvas Library

Thanks for helping improve Canvas Library. This project is MIT-licensed and built for people who use [Cursor](https://cursor.com) canvases and markdown as working documents.

## Ways to help

- Fix bugs or polish macOS / SwiftUI UX
- Improve scanning, search, or the Finder-like sidebar
- Docs, screenshots, and setup clarity
- Small, well-scoped features that stay true to “Cursor companion, not a full IDE”

If you’re unsure whether an idea fits, open an issue first.

## Development setup

1. **macOS 14+**, **Xcode 15+**
2. **Node.js** with `npx` on your `PATH` (canvas preview uses esbuild)
3. Optional but recommended: **Cursor** installed (canvas runtime fallback)

```bash
git clone git@github.com:rloechner/canvas-library.git
cd canvas-library
open CanvasLibrary.xcodeproj
# Signing: set *your* Development Team
# Product → Run (⌘R)
```

Or from the CLI:

```bash
xcodebuild -project CanvasLibrary.xcodeproj -scheme CanvasLibrary \
  -configuration Debug -derivedDataPath /tmp/CanvasLibraryDD build
```

### Common gotchas

| Issue | Fix |
|-------|-----|
| Codesign / “resource fork” errors | Keep Derived Data **outside** iCloud Desktop & Documents (`-derivedDataPath /tmp/CanvasLibraryDD`) |
| Canvas preview missing runtime | Install Cursor, or place a **private** local `canvas-runtime.esm.js` under `CanvasLibrary/Resources/CanvasHost/` for dev only — see [THIRD_PARTY.md](./THIRD_PARTY.md) |
| Signing team mismatch | Change the team in Xcode; don’t commit secrets or personal certs |

## Pull requests

- **One concern per PR** when practical (feature *or* fix *or* docs)
- Match existing Swift / SwiftUI style: clear names, small views, `@MainActor` for UI state
- Don’t commit `DerivedData/`, `dist/`, user scheme state, `.DS_Store`, or large unrelated binaries
- **Do not** add or commit Cursor’s proprietary `canvas-runtime.esm.js` (it is gitignored for a reason)
- Update README / THIRD_PARTY if you change requirements, runtime resolution, or licensing surface
- In the PR body: *what* changed, *why*, and how you verified (build, manual preview, etc.)

## Code of conduct

Be respectful and constructive. Harassment or bad-faith contributions are not welcome. Many communities adopt the [Contributor Covenant](https://www.contributor-covenant.org/) as a shared baseline.

## License

By contributing, you agree that your contributions are licensed under the project’s [MIT License](./LICENSE).
