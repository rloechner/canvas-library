#!/usr/bin/env bash
# Smoke-check Canvas Host contract (host + shim + design-mode + runtime resolution).
# Does not ship or redistribute Cursor's proprietary runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$ROOT/CanvasLibrary/Resources/CanvasHost"
FAIL=0

ok() { printf '  OK  %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; FAIL=1; }

echo "Canvas Library — canvas host smoke"
echo "Host dir: $HOST"
echo

# --- First-party assets always required ---
for f in host.html canvas-shim.js design-mode.js minimal-canvas-runtime.esm.js; do
  if [[ -f "$HOST/$f" ]]; then
    ok "present $f"
  else
    bad "missing $f"
  fi
done

# --- host.html contract ---
if grep -q 'mountCanvas' "$HOST/host.html"; then
  ok "host.html references mountCanvas"
else
  bad "host.html missing mountCanvas"
fi
if grep -q 'canvas-runtime.esm.js' "$HOST/host.html"; then
  ok "host.html imports canvas-runtime.esm.js"
else
  bad "host.html does not import canvas-runtime.esm.js"
fi
if grep -q 'design-mode.js' "$HOST/host.html"; then
  ok "host.html loads design-mode.js"
else
  bad "host.html missing design-mode.js"
fi

# --- shim exports used by sample canvases ---
for export_name in Stack Text H1 Card CardBody CardHeader Grid Row Pill Stat Callout; do
  if grep -q "export const $export_name" "$HOST/canvas-shim.js"; then
    ok "shim exports $export_name"
  else
    bad "shim missing export $export_name"
  fi
done

# --- design-mode bridge ---
if grep -q 'CanvasLibraryDesign' "$HOST/design-mode.js"; then
  ok "design-mode exposes CanvasLibraryDesign"
else
  bad "design-mode missing CanvasLibraryDesign"
fi
if grep -q 'designEdit' "$HOST/design-mode.js"; then
  ok "design-mode posts designEdit"
else
  bad "design-mode missing designEdit bridge"
fi

# --- minimal open runtime contract ---
if grep -q 'export async function mountCanvas' "$HOST/minimal-canvas-runtime.esm.js"; then
  ok "minimal runtime exports mountCanvas"
else
  bad "minimal runtime missing mountCanvas"
fi
if grep -q 'globalThis.React' "$HOST/minimal-canvas-runtime.esm.js"; then
  ok "minimal runtime installs globalThis.React"
else
  bad "minimal runtime does not install React"
fi

# --- optional proprietary runtime (local only; must not be required) ---
if [[ -f "$HOST/canvas-runtime.esm.js" ]]; then
  ok "local canvas-runtime.esm.js present (dev convenience; do not commit)"
  if grep -q 'mountCanvas' "$HOST/canvas-runtime.esm.js"; then
    ok "local runtime mentions mountCanvas"
  else
    bad "local runtime does not mention mountCanvas"
  fi
else
  ok "no local canvas-runtime.esm.js (expected for clean public trees)"
fi

# --- Cursor.app fallback path probe (informational) ---
CURSOR_RUNTIME=""
for rel in \
  "Contents/Resources/app/extensions/cursor-agent-exec/dist/canvas-runtime/canvas-runtime.esm.js" \
  "Contents/Resources/app/extensions/cursor-local-agent-runtime/dist/canvas-runtime/canvas-runtime.esm.js"
do
  for root in "/Applications/Cursor.app" "$HOME/Applications/Cursor.app"; do
    if [[ -f "$root/$rel" ]]; then
      CURSOR_RUNTIME="$root/$rel"
      break 2
    fi
  done
done
if [[ -n "$CURSOR_RUNTIME" ]]; then
  ok "Cursor.app runtime found: $CURSOR_RUNTIME"
else
  ok "Cursor.app runtime not installed (minimal host will be used)"
fi

# --- Node / esbuild availability ---
if command -v node >/dev/null 2>&1; then
  ok "node on PATH: $(command -v node) ($(node -v 2>/dev/null || true))"
else
  bad "node not on PATH (canvas compile needs npx esbuild)"
fi
if command -v npx >/dev/null 2>&1; then
  ok "npx on PATH: $(command -v npx)"
else
  bad "npx not on PATH"
fi

# --- Optional: compile sample canvas with esbuild (no full WKWebView) ---
SAMPLE="$ROOT/Samples/demo-library/harbor-desk/canvases/onboarding-review.canvas.tsx"
if [[ -f "$SAMPLE" ]] && command -v npx >/dev/null 2>&1; then
  TMP="$(mktemp -d /tmp/canvaslibrary-smoke-XXXXXX)"
  OUT="$TMP/canvas-module.js"
  if npx --yes esbuild@0.25.4 "$SAMPLE" \
      --outfile="$OUT" \
      --format=esm \
      --platform=browser \
      --target=es2020 \
      --jsx=transform \
      --jsx-factory=React.createElement \
      --jsx-fragment=React.Fragment \
      --loader:.tsx=tsx \
      --log-level=error; then
    if [[ -s "$OUT" ]]; then
      ok "esbuild compiled sample onboarding-review.canvas.tsx"
    else
      bad "esbuild produced empty output"
    fi
  else
    bad "esbuild failed on sample canvas"
  fi
  rm -rf "$TMP"
else
  ok "skip esbuild sample (missing sample or npx)"
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "Smoke FAILED"
  exit 1
fi
echo "Smoke PASSED"
exit 0
