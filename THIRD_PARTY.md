# Third-party components

Canvas Library is MIT-licensed. This file lists third-party software and notes about components that are **not** part of that MIT grant.

## Monaco Editor

- **License:** MIT (Microsoft)
- **Use:** In-app source editor (`CanvasLibrary/Resources/EditorHost/monaco/`)
- **Upstream:** [microsoft/monaco-editor](https://github.com/microsoft/monaco-editor)

## esbuild

- **License:** MIT
- **Use:** On-device transpile of `.canvas.tsx` via `npx esbuild` (not vendored in this repo)
- **Upstream:** [evanw/esbuild](https://github.com/evanw/esbuild)

Canvas preview requires **Node.js / npx** so the app can run a pinned esbuild version at compile time.

## Cursor canvas runtime

- **Component:** `canvas-runtime.esm.js` (and related Cursor packages)
- **Origin:** Bundled inside [Cursor](https://cursor.com) (Anysphere), e.g.  
  `/Applications/Cursor.app/Contents/Resources/app/extensions/cursor-agent-exec/dist/canvas-runtime/`
- **Status:** Proprietary Cursor software — **not** covered by this project’s MIT license

### Redistribution

**Redistributing Cursor’s proprietary canvas runtime may be restricted** by Cursor’s terms of use / EULA. Do **not** assume you may ship `canvas-runtime.esm.js` in public binaries, app releases, or source archives.

### How Canvas Library uses it

The app prefers a runtime only when it is already available locally:

1. **Bundled** — if `Resources/CanvasHost/canvas-runtime.esm.js` is present in the app bundle (local/dev convenience)
2. **Source tree** — same path under `CanvasLibrary/Resources/CanvasHost/` when running from Xcode
3. **Cursor install fallback** — copy from a local `Cursor.app` into a user cache and pair it with first-party host files

First-party host assets that **do** ship with this project (MIT):

- `host.html`
- `canvas-shim.js` (maps `cursor/canvas` imports to runtime globals)
- `design-mode.js` (unlock-preview editing bridge)

### Clean public release practice

- Prefer **not** committing or publishing `canvas-runtime.esm.js`
- Document that users need **Cursor installed** (or a private local copy for development)
- Keep this notice in redistributions of Canvas Library itself

## Prettier (optional)

- Format-on-command for TSX uses Node tooling when available (e.g. Prettier via the app’s formatter path). Same “run via local Node” model as esbuild — not a hard vendored dependency of the MIT tree.

## Affiliation

Canvas Library is an independent open-source project. It is **not affiliated with, endorsed by, or sponsored by** Anysphere or Cursor.
