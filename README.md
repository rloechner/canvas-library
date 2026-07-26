# Canvas Library

**Your working Cursor documents, in their own space.**

Canvas Library is a macOS companion for [Cursor](https://cursor.com) canvases (`.canvas.tsx`) and markdown notes. Find documents across every project, open them in a focused window, preview live, unlock-edit text in the preview, and lightly edit source — without digging through chat history or switching projects just to reopen a canvas.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)](#requirements)
[![Swift / SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-orange.svg)](#build--run)

> **Not affiliated with Anysphere or Cursor.** Independent open-source project.

---

## Why it exists

Cursor canvases are great for product thinking, UX reviews, and agent-assisted UI — but they live buried under `~/.cursor/projects/.../canvases`. Markdown notes for agents and docs scatter the same way.

Canvas Library treats those files as a **working library**:

- Browse every project’s canvases and markdown in one place
- Jump back into a canvas without reopening the whole workspace
- Preview, edit, save — then keep shipping in Cursor

## Features

| Area | What you get |
|------|----------------|
| **Library** | Scans `~/.cursor/projects/*/canvases` recursively for `.canvas.tsx` and `.md` |
| **Finder-like sidebar** | Projects A–Z → nested folders (only places files exist) → documents |
| **Filter & search** | All / Canvases / Markdown; search by title, path, or project |
| **Cycle** | ⌘↑ / ⌘↓ through the filtered list |
| **Canvas preview** | Live render via esbuild + canvas runtime |
| **Markdown preview** | Local HTML preview |
| **Unlock preview** | Click text in a canvas to edit; changes write through to source |
| **Source** | Monaco editor (TSX / Markdown) |
| **Outline** | Structure sidebar for the open document |
| **Format** | Prettier for TSX when Node is available; light normalize for MD |
| **Save / Revert** | Write to disk or discard unsaved changes |
| **Custom spaces** | Add extra folders beyond the default Cursor scan |
| **Open with** | Open `.tsx` / `.md` files into the library |

## Requirements

| Requirement | Notes |
|-------------|--------|
| **macOS 14+** | Deployment target 14.0 |
| **Xcode 15+** | To build from source |
| **Node.js / npx** | Canvas compile uses `npx esbuild` |
| **Cursor (recommended)** | Fallback source for the canvas runtime if not bundled |

### Canvas runtime

Preview needs a **canvas runtime**. Resolution order:

1. App bundle `Resources/CanvasHost/canvas-runtime.esm.js`
2. Source tree `CanvasLibrary/Resources/CanvasHost/canvas-runtime.esm.js`
3. Local **Cursor.app** install (see [THIRD_PARTY.md](./THIRD_PARTY.md))

First-party host files (`host.html`, `canvas-shim.js`, `design-mode.js`) always ship with this repo.

> **Do not commit or redistribute** Cursor’s proprietary `canvas-runtime.esm.js`. It is gitignored on purpose. Install Cursor (or keep a private local copy for development). Details: [THIRD_PARTY.md](./THIRD_PARTY.md).

## Quick start

```bash
git clone git@github.com:rloechner/canvas-library.git
cd canvas-library
open CanvasLibrary.xcodeproj
```

In Xcode:

1. Select your **Team** under Signing & Capabilities (change the sample team if needed)
2. Select the **CanvasLibrary** scheme
3. **Product → Run** (⌘R)

With Cursor installed and Node on your `PATH`, open a canvas from the sidebar and use **Preview**.

### Command-line build

```bash
xcodebuild -project CanvasLibrary.xcodeproj -scheme CanvasLibrary \
  -configuration Debug -derivedDataPath /tmp/CanvasLibraryDD build
```

If the repo lives under **iCloud Desktop & Documents**, codesign can fail with *resource fork / Finder information* errors when DerivedData is inside that tree. Point Derived Data outside iCloud (as above, or Xcode → Settings → Locations).

| Project | Value |
|---------|--------|
| Display name | Canvas Library |
| Bundle ID | `com.ryanloechner.canvaslibrary` |
| Default team (maintainer) | `44N969GC55` — **replace with your own** when forking |

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open file |
| ⌘↑ / ⌘↓ | Previous / next document |
| ⌘R | Reload preview |
| ⌥⌘F | Format document |
| ⌘S | Save |
| ⇧⌘Z | Revert unsaved changes |
| ⇧⌘R | Rescan library |
| ⇧⌘C | Copy source |

## Project layout

```text
CanvasLibrary.xcodeproj
CanvasLibrary/
  CanvasLibraryApp.swift
  ContentView.swift
  Models/           # documents, app state, library tree
  Services/         # scanner, esbuild compile, format, rewrite
  Views/            # sidebar, Monaco, canvas / markdown preview
  Resources/
    CanvasHost/     # host.html, shim, design-mode (+ optional runtime)
    EditorHost/     # Monaco editor host
Samples/
scripts/            # release signing & notarization helpers
```

## Contributing

Contributions are welcome — bug fixes, UX polish, docs, and focused features.

1. Fork the repo and create a branch
2. Build with Xcode (see [CONTRIBUTING.md](./CONTRIBUTING.md))
3. Keep PRs focused; match existing SwiftUI style
4. **Never** commit Cursor’s proprietary runtime or secrets

Please read **[CONTRIBUTING.md](./CONTRIBUTING.md)** before opening a PR.

## License

**MIT** — see [LICENSE](./LICENSE).

Third-party components and Cursor runtime notes: **[THIRD_PARTY.md](./THIRD_PARTY.md)**

| Component | License / notes |
|-----------|-----------------|
| Monaco Editor | MIT (Microsoft) |
| esbuild | MIT (via `npx`; not vendored) |
| Cursor canvas runtime | Proprietary — local use / Cursor install fallback only |

## Status

Steady **v1**: library → preview → unlock-edit → save works as a Cursor companion. Built for people who live in canvases and want them one keystroke away.

---

Made with care for the Cursor community · [MIT](./LICENSE) · Independent project, not affiliated with Anysphere
