# Agent notes — Canvas Library

Context for humans and AI agents working on this repo. **Read this first** after the README.

## Product identity

| | |
|---|---|
| Name | **Canvas Library** |
| Repo | https://github.com/rloechner/canvas-library |
| Bundle ID | `com.ryanloechner.canvaslibrary` |
| Team | `44N969GC55` (Ryan Loechner) |
| License | MIT |
| Platform | macOS 14+, SwiftUI |
| Current release | **v1.1.0** (see GitHub Releases for DMG) |

Independent Cursor companion — **not** affiliated with Anysphere. Do not ship Cursor’s proprietary `canvas-runtime.esm.js` (gitignored; see `THIRD_PARTY.md`).

## What the app is

A small utility to **find, preview, and lightly edit** working documents:

- **Canvases** — `.canvas.tsx` (live preview via esbuild + canvas runtime, unlock-preview text edit)
- **Markdown** — `.md` / `.markdown` (HTML preview + Monaco source)

Library folders are **user-controlled**. There is **no automatic scan** of `~/.cursor/projects` unless the user adds the opt-in “Cursor canvases” space.

## Architecture (high level)

```
CanvasLibrary/
  CanvasLibraryApp.swift    # @main, menus, open-with
  ContentView.swift         # NavigationStack + HSplitView (sidebar | detail)
  Models/
    AppModel.swift          # @MainActor ObservableObject — library, buffer, compile, prefs
    WorkingDocument.swift   # DocumentKind, WorkingDocument, DocumentSpace, LibraryFilter, tree builder
  Services/
    LibraryScanner.swift    # Recursive scan of configured spaces
    CanvasCompiler.swift    # esbuild + host assets → temp work dir
    SourceTextRewriter.swift
    MarkdownRenderer.swift, TSXFormatter, outline parser, …
  Views/
    LibrarySidebar.swift    # Search, Both|Canvases|Markdown, project tree, context menus
    FirstLaunchView.swift   # One-time setup sheet
    CanvasPreviewView.swift # WKWebView + design-mode bridge
    MonacoEditorView.swift / SourceCodeView.swift
    MarkdownPreviewView.swift, SettingsView, EmptyStateView
  Resources/
    CanvasHost/             # host.html, canvas-shim.js, design-mode.js (+ optional runtime)
    EditorHost/             # Monaco
scripts/
  build-release.sh          # Developer ID sign + DMG (uses /tmp for DerivedData)
  notarize.sh               # notarytool + staple
```

### Layout note (important)

**Do not reintroduce `NavigationSplitView` for the main chrome** without checking geometry. It was laying out ~2× window height and drawing the sidebar **above the title bar**. Current pattern: `NavigationStack` + `HSplitView` + plain sidebar `VStack` (search → filter → `List` → footer).

### Library / spaces

| Concept | Behavior |
|---------|----------|
| Spaces | `[DocumentSpace]` — folders the user added |
| Persistence | `UserDefaults` key `canvaslibrary.librarySpaces` (JSON) |
| First launch | `canvaslibrary.didCompleteSetup`; `AppModel.needsSetup` → sheet `FirstLaunchView` |
| Cursor root | Factory `DocumentSpace.allCursorCanvases()` — **opt-in only** via `addCursorCanvasesSpace()` |
| Migration | Legacy `canvaslibrary.extraSpaces` + other prefs → one-time promote to librarySpaces |
| Scan | `LibraryScanner.scan(spaces:)` — recursive; skips `node_modules`, `.git`, etc. |
| Empty spaces | No scan / no retry thrash |

### Document kinds & edit loop

Both kinds share: open → `bufferText` / `originalText` / `isDirty` → Monaco Source → Save / Revert / Format → Preview.

| Kind | Preview | Format | Special |
|------|---------|--------|---------|
| Canvas | Compile + WKWebView host; unlock design-mode | Prettier when Node available | Design mode rewrites source via `SourceTextRewriter` |
| Markdown | `MarkdownRenderer` HTML | Trailing-whitespace normalize | No design-mode |

Dirty navigation: Save / Don’t Save / Cancel before switching docs.

### Sidebar UX

- Filter: **Both | Canvases | Markdown** (segmented under search; persisted as `canvaslibrary.libraryFilter`)
- Context menus: move project up/down, hide project, hide folder, reveal in Finder, remove **space** (not delete files)
- Settings: manage spaces, restore hidden projects/folders, editor prefs

### UserDefaults keys (prefix `canvaslibrary.`)

| Key | Purpose |
|-----|---------|
| `librarySpaces` | Full space list JSON |
| `didCompleteSetup` | First-launch completed |
| `libraryFilter` | `all` / `canvases` / `markdown` |
| `extraSpaces` | **Legacy read-only** migration |
| `recentIDs` | Paths (max 20); **no UI yet** |
| `expandedProjects` / `expandedFolders` | Outline expand state |
| `projectOrder` | Sidebar project order |
| `hiddenProjects` / `excludedFolders` | Hide without deleting |
| `fontSize` / `showLineNumbers` | Editor prefs |

### Known gaps / dead code

- `OutlineSidebar.swift` is empty; outline parse still runs for canvas but jump-to-line is not fully wired.
- `recentDocuments` has no UI.
- No filesystem watcher — external edits need Rescan.
- Scanner only picks `*.canvas.tsx` + md; Open panel may open plain `.tsx` as canvas.

## Build & release

```bash
# Debug (DerivedData outside iCloud if repo is under Documents)
xcodebuild -scheme CanvasLibrary -configuration Debug \
  -derivedDataPath /tmp/CanvasLibrary-DD build
open /tmp/CanvasLibrary-DD/Build/Products/Debug/CanvasLibrary.app

# Release DMG (Developer ID)
./scripts/build-release.sh --dmg

# Notarize (Keychain profile AC_PASSWORD already used on maintainer machine)
NOTARY_PROFILE=AC_PASSWORD ./scripts/notarize.sh dist/Canvas-Library-x.y.z.dmg

# GitHub release
gh release create vX.Y.Z dist/Canvas-Library-X.Y.Z.dmg --title "…" --notes "…"
```

Signing identity: `Developer ID Application: Ryan Loechner (44N969GC55)`.  
Release builds must use **DerivedData under `/tmp`** (script default) to avoid iCloud xattr codesign failures.

## Conventions for changes

- Prefer focused diffs; match existing SwiftUI / `@MainActor` AppModel style.
- Never commit `canvas-runtime.esm.js`, secrets, or DerivedData.
- Keep canvas + markdown **feature parity** on open/edit/save/revert unless intentionally diverging.
- Update this file + README when product model or layout shell changes.

## Quick “start here” for a new agent

1. Repo lives at `~/Documents/Apps/CanvasLibrary` (GitHub: `rloechner/canvas-library`).  
2. Read README + this file.  
3. Skim `AppModel.swift` (spaces, open/save, compile).  
4. Skim `ContentView.swift` + `LibrarySidebar.swift` + `FirstLaunchView.swift`.  
5. Build with `/tmp/CanvasLibrary-DD`.  
6. Ask the user before version bumps, releases, or destructive git history.  

**Naming:** product is **Canvas Library** / `CanvasLibrary` / `com.ryanloechner.canvaslibrary`. Do not reintroduce the old name **TSXPretty**. Service files named `TSXFormatter` etc. refer to TypeScript/TSX file format, not the product.
