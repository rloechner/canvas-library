# Canvas Library

**Your working Cursor documents, in their own space.**

A macOS companion for [Cursor](https://cursor.com) canvases (`.canvas.tsx`) and markdown notes — browse a library across projects, cycle through docs, preview live, unlock-edit text in preview, and lightly edit source without hunting chat history.

**Not affiliated with Anysphere / Cursor.**

## Features

- **Library** — scans `~/.cursor/projects/*/canvases` for `.canvas.tsx` and `.md`
- **Filters** — All / Canvases / Markdown
- **Search** — by title, file name, project
- **Recent** — quick re-open of recent documents
- **Cycle** — ⌘↑ / ⌘↓ previous / next in the filtered list
- **Preview**
  - Canvases: live render (esbuild + canvas runtime)
  - Markdown: local HTML preview
- **Unlock preview** — click text in the canvas to edit; writes through to source
- **Source** — Monaco editor (syntax-colored TSX / MD)
- **Outline** — structure sidebar for the open document
- **Format** — Prettier for TSX when Node is available; light normalize for MD
- **Save / Revert** — write to disk or discard unsaved changes
- **Custom spaces** — add extra folders of docs beyond the default Cursor scan
- **Open with** — open `.tsx` / `.md` files into the library

## Requirements

| Requirement | Notes |
|---|---|
| **macOS 14+** | Deployment target 14.0 |
| **Xcode 15+** | To build from source |
| **Node.js / npx** | Canvas compile via esbuild (`npx esbuild`) |
| **Cursor (optional)** | Fallback for `canvas-runtime.esm.js` if not bundled |

Canvas preview needs a **canvas runtime**. Resolution order:

1. App bundle `Resources/CanvasHost/canvas-runtime.esm.js`
2. Source tree `CanvasLibrary/Resources/CanvasHost/canvas-runtime.esm.js`
3. Local **Cursor.app** install (see [THIRD_PARTY.md](./THIRD_PARTY.md))

If none of these are available, the app shows a clear error with install instructions. First-party host files (`host.html`, `canvas-shim.js`, `design-mode.js`) always ship with the project.

## Build & run

```bash
cd /path/to/this/repo
open CanvasLibrary.xcodeproj
```

In Xcode:

1. Select the **CanvasLibrary** scheme
2. **Product → Run** (⌘R)

Project metadata:

| Key | Value |
|---|---|
| Display name | Canvas Library |
| Bundle ID | `com.ryanloechner.canvaslibrary` |
| Development team | `44N969GC55` (Ryan Loechner) — change for your signing identity |

### Command-line build (optional)

```bash
xcodebuild -project CanvasLibrary.xcodeproj -scheme CanvasLibrary -configuration Debug build
```

If the repo lives under **iCloud Drive / Desktop & Documents**, codesign may fail with *“resource fork, Finder information, or similar detritus not allowed”* when DerivedData is inside that tree. Point Derived Data elsewhere:

```bash
xcodebuild -project CanvasLibrary.xcodeproj -scheme CanvasLibrary \
  -configuration Debug -derivedDataPath /tmp/CanvasLibraryDD build
```

In Xcode: **Settings → Locations → Derived Data → Custom** (path outside iCloud).

### Canvas runtime for developers

- **Recommended:** keep [Cursor](https://cursor.com) installed; the app falls back to its runtime automatically.
- **Optional local copy:** place `canvas-runtime.esm.js` in `CanvasLibrary/Resources/CanvasHost/` for offline/dev builds.
- **Do not redistribute** Cursor’s proprietary runtime in public releases without permission — see [THIRD_PARTY.md](./THIRD_PARTY.md).

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘O | Open file |
| ⌘↑ / ⌘↓ | Previous / next document |
| ⌘R | Reload preview |
| ⌥⌘F | Format document |
| ⌘S | Save |
| ⇧⌘Z | Revert unsaved changes |
| ⇧⌘R | Rescan library |
| ⇧⌘C | Copy source |

## Project layout

```
CanvasLibrary.xcodeproj
CanvasLibrary/
  CanvasLibraryApp.swift
  ContentView.swift
  Models/           # library docs, app state
  Services/         # scanner, esbuild compile, format, rewrite
  Views/            # sidebar, Monaco, canvas/markdown preview
  Resources/
    CanvasHost/     # host.html, shim, design-mode (+ optional runtime)
    EditorHost/     # Monaco editor host
Samples/
```

## Product direction

Canvas Library is a **Cursor companion**, not an IDE or notes-app replacement. Canvases are first-class; markdown is the natural co-tenant for agent instructions and internal docs.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

**MIT** — see [LICENSE](./LICENSE).

Third-party components and **Cursor runtime redistribution notes** are documented in [THIRD_PARTY.md](./THIRD_PARTY.md):

- **Monaco Editor** — MIT (Microsoft)
- **esbuild** — MIT (invoked via npx; not vendored)
- **Cursor canvas runtime** — proprietary; local use / Cursor install fallback only; redistributing may be restricted

## Status

Steady **v1** — core library → preview → unlock-edit → save loop works. Independent OSS project; not affiliated with Cursor.
