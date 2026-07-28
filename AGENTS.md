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
| Current release | **v1.3.0** (see GitHub Releases for DMG) |

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

### Unsaved multi-doc buffers

- Switching documents **parks** dirty buffers (no discard prompt).
- `dirtyDocumentIDs` + orange **dot** on sidebar rows.
- Returning to a parked doc restores unsaved text.
- Save clears parked state for that path.

### Git

Thin shell-out via system `git` (`Services/GitService.swift` + `Views/GitSheets.swift`):

- Root: walk up from file, **or** decode Cursor `~/.cursor/projects/<Users-…>` → real workspace and use that repo  
- If file is **outside** worktree (Cursor cache): show branch, disable stage/commit/discard with clear help text  
- Prefer adding the **real project folder** as a library space so canvases on disk track with git  
- Header: status capsule + Diff / **Discard** / Stage|Unstage / Commit; status bar: branch  
- Dirty buffer → Save before stage/commit  
- **Two different “undo”s** (do not conflate):
  - **Revert** — discard *unsaved buffer* edits → last save on disk (`isDirty`)
  - **Discard** — `git restore` to HEAD (staged + worktree) after save when still modified (`canDiscardGitChanges`)
- Sidebar: orange **dot** = unsaved buffer; git letter badge **M/A/U/D…** when committed status is dirty (`gitStatusByDocumentID`, refreshed after scan/save/stage/commit/discard)
- Diff sheet: footer actions for Discard / Stage / Commit  

**Not in v1:** push/pull, branch switch, multi-file staging, history, force ops.

### PDF export & print

- Toolbar **Export PDF** / **Print**, File menu **Export as PDF…** (⇧⌘E) / **Print…** (⌘P)
- Shared pipeline: `AppModel.renderCurrentDocumentPDF()` → `PDFExporter` (window-hosted `WKWebView` + `createPDF`)
- Markdown: print-styled HTML (`MarkdownRenderer` `forPrint`); canvas: preview host if ready (longer settle), else monospaced source dump
- Print: render PDF data → `PDFKit` `PDFDocument.printOperation` system panel
- Dirty buffer: Save & Continue / Continue with Buffer / Cancel

### Library liveness & environment

- **FSEvents watcher** (`LibraryFileWatcher`) on configured space roots; debounced partial rescan per affected space.
- **External change**: mtime/size stamp on open/save; auto-reload when clean; banner (Reload / Keep Editing) when dirty.
- **Canvas environment**: `CanvasEnvironment.probe()` → Node + runtime source; status-bar badge + compile error help.
- **Runtime order**: app bundle → source tree → Cursor.app → **minimal open host** (`minimal-canvas-runtime.esm.js`, limited stubs).
- **Outline**: toolbar Outline menu jumps to Monaco line (`pendingScrollToLine` + `revealLine`).
- **Recents**: File menu **Open Recent** (paths in `recentIDs`).
- Smoke: `scripts/smoke-canvas-host.sh` (host/shim/design-mode/minimal runtime/esbuild sample).

### Known gaps / dead code

- Outline is canvas/TSX-oriented (not markdown headings).
- Minimal host is intentionally limited vs Cursor component fidelity.
- Scanner only picks `*.canvas.tsx` + md; Open panel may open plain `.tsx` as canvas.
- Manual **Rescan** remains as recovery; watcher covers the common path.

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
