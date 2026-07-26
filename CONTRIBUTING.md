# Contributing to Canvas Library

Thanks for helping improve Canvas Library.

## How to build

1. **macOS 14+**, Xcode 15+
2. **Node.js** with `npx` on your `PATH` (canvas preview uses esbuild)
3. Optional but recommended: **Cursor** installed for canvas runtime fallback

```bash
open CanvasLibrary.xcodeproj
# Product → Run (⌘R)
```

Or:

```bash
xcodebuild -project CanvasLibrary.xcodeproj -scheme CanvasLibrary -configuration Debug build
```

If codesign fails with Finder information / resource-fork errors and the project is under iCloud Desktop & Documents, use a Derived Data path outside iCloud (e.g. `-derivedDataPath /tmp/CanvasLibraryDD`).

If canvas preview fails with a missing runtime, install Cursor or place a local `canvas-runtime.esm.js` under `CanvasLibrary/Resources/CanvasHost/` (development only — see [THIRD_PARTY.md](./THIRD_PARTY.md)).

## Pull requests

- Keep PRs focused: one feature or fix per PR when practical
- Match existing Swift / SwiftUI style (clear names, small views, `@MainActor` for UI state)
- Don’t commit DerivedData, user schemes state, or large binaries unrelated to the change
- **Do not** add or commit Cursor’s proprietary `canvas-runtime.esm.js` for redistribution; document fallbacks instead
- Update README / THIRD_PARTY notes if you change runtime resolution, requirements, or licensing surface
- Describe *what* and *why* in the PR body; link issues if any

## Code of conduct

Be respectful and constructive. Harassment or bad-faith contributions are not welcome. For a full template communities often adopt, see the [Contributor Covenant](https://www.contributor-covenant.org/).

## License

By contributing, you agree that your contributions are licensed under the project’s [MIT License](./LICENSE).
