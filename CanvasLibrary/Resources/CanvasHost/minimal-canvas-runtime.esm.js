/**
 * Canvas Library — minimal open canvas runtime (fallback).
 *
 * Used when Cursor’s proprietary canvas-runtime.esm.js is unavailable.
 * Implements mountCanvas + a small React-compatible renderer and stub
 * cursor/canvas components so simple canvases can still preview.
 *
 * Not a full Cursor canvas fidelity target — expect visual differences.
 */
/* eslint-disable no-unused-vars */

const EMPTY = {};

function flattenChildren(children) {
  const out = [];
  const walk = (c) => {
    if (c == null || c === false || c === true) return;
    if (Array.isArray(c)) {
      c.forEach(walk);
      return;
    }
    out.push(c);
  };
  walk(children);
  return out;
}

function createElement(type, props, ...children) {
  const p = props ? { ...props } : {};
  const fromProps = p.children;
  delete p.children;
  const all = flattenChildren([fromProps, ...children]);
  if (all.length === 1) p.children = all[0];
  else if (all.length > 1) p.children = all;
  return { $$typeof: Symbol.for("react.element"), type, props: p, key: p.key ?? null };
}

const Fragment = Symbol.for("react.fragment");

function isValidElement(el) {
  return el != null && typeof el === "object" && el.$$typeof === Symbol.for("react.element");
}

const React = {
  createElement,
  Fragment,
  isValidElement,
  version: "0.0.0-canvas-library-minimal",
  useState(initial) {
    // Stateless fallback: hooks are no-ops beyond first render value.
    const v = typeof initial === "function" ? initial() : initial;
    return [v, () => {}];
  },
  useEffect() {},
  useMemo(fn) {
    return fn();
  },
  useCallback(fn) {
    return fn;
  },
  useRef(initial) {
    return { current: initial };
  },
  useContext() {
    return undefined;
  },
};

function applyStyle(el, style) {
  if (!style || typeof style !== "object") return;
  for (const [k, v] of Object.entries(style)) {
    if (v == null) continue;
    const cssKey = k.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase());
    el.style[cssKey] = typeof v === "number" && !String(k).includes("opacity") && k !== "zIndex" && k !== "fontWeight"
      ? `${v}px`
      : String(v);
  }
}

function setProps(el, props) {
  if (!props) return;
  for (const [key, value] of Object.entries(props)) {
    if (key === "children" || key === "key" || key === "ref") continue;
    if (key === "style") {
      applyStyle(el, value);
      continue;
    }
    if (key === "className") {
      el.className = value == null ? "" : String(value);
      continue;
    }
    if (key.startsWith("on") && typeof value === "function") {
      const event = key.slice(2).toLowerCase();
      el.addEventListener(event, value);
      continue;
    }
    if (value === false || value == null) continue;
    if (value === true) {
      el.setAttribute(key, "");
      continue;
    }
    try {
      el.setAttribute(key, String(value));
    } catch (_) {
      /* ignore invalid attrs */
    }
  }
}

function renderNode(vnode, container) {
  if (vnode == null || vnode === false || vnode === true) return;
  if (typeof vnode === "string" || typeof vnode === "number") {
    container.appendChild(document.createTextNode(String(vnode)));
    return;
  }
  if (Array.isArray(vnode)) {
    vnode.forEach((c) => renderNode(c, container));
    return;
  }
  if (!isValidElement(vnode)) {
    container.appendChild(document.createTextNode(String(vnode)));
    return;
  }

  const { type, props } = vnode;
  const p = props || EMPTY;

  if (type === Fragment) {
    renderNode(p.children, container);
    return;
  }

  if (typeof type === "function") {
    let result;
    try {
      result = type(p);
    } catch (err) {
      const pre = document.createElement("pre");
      pre.style.cssText = "color:#b00020;padding:12px;white-space:pre-wrap;font:12px/1.4 monospace";
      pre.textContent = err && err.stack ? err.stack : String(err);
      container.appendChild(pre);
      return;
    }
    renderNode(result, container);
    return;
  }

  if (typeof type !== "string") {
    renderNode(p.children, container);
    return;
  }

  const el = document.createElement(type);
  setProps(el, p);
  renderNode(p.children, el);
  container.appendChild(el);
}

function render(vnode, container) {
  while (container.firstChild) container.removeChild(container.firstChild);
  renderNode(vnode, container);
}

// --- cursor/canvas-style stubs ------------------------------------------------

function gapStyle(gap) {
  if (gap == null) return undefined;
  return typeof gap === "number" ? `${gap}px` : String(gap);
}

function Stack({ children, gap, style, direction, align, justify, wrap, ...rest }) {
  return createElement(
    "div",
    {
      ...rest,
      style: {
        display: "flex",
        flexDirection: direction === "row" ? "row" : "column",
        alignItems: align || "stretch",
        justifyContent: justify || "flex-start",
        flexWrap: wrap ? "wrap" : undefined,
        gap: gapStyle(gap),
        ...style,
      },
    },
    children
  );
}

function Row({ children, gap, style, align, justify, wrap, ...rest }) {
  return createElement(
    "div",
    {
      ...rest,
      style: {
        display: "flex",
        flexDirection: "row",
        alignItems: align || "center",
        justifyContent: justify || "flex-start",
        flexWrap: wrap ? "wrap" : "wrap",
        gap: gapStyle(gap ?? 8),
        ...style,
      },
    },
    children
  );
}

function Grid({ children, columns, gap, style, ...rest }) {
  const cols =
    typeof columns === "number"
      ? `repeat(${columns}, minmax(0, 1fr))`
      : columns || "1fr";
  return createElement(
    "div",
    {
      ...rest,
      style: {
        display: "grid",
        gridTemplateColumns: cols,
        gap: gapStyle(gap ?? 12),
        ...style,
      },
    },
    children
  );
}

function Text({ children, tone, size, style, ...rest }) {
  const color =
    tone === "secondary" || tone === "muted"
      ? "var(--cl-muted, #6b7280)"
      : tone === "danger"
        ? "#b00020"
        : undefined;
  const fontSize = size === "small" ? 13 : size === "large" ? 16 : 14;
  return createElement(
    "span",
    {
      ...rest,
      style: { color, fontSize, lineHeight: 1.45, ...style },
    },
    children
  );
}

function H1({ children, style, ...rest }) {
  return createElement("h1", { ...rest, style: { margin: "0 0 8px", fontSize: 28, fontWeight: 650, ...style } }, children);
}
function H2({ children, style, ...rest }) {
  return createElement("h2", { ...rest, style: { margin: "0 0 6px", fontSize: 20, fontWeight: 600, ...style } }, children);
}
function H3({ children, style, ...rest }) {
  return createElement("h3", { ...rest, style: { margin: "0 0 4px", fontSize: 16, fontWeight: 600, ...style } }, children);
}

function Card({ children, style, ...rest }) {
  return createElement(
    "div",
    {
      ...rest,
      style: {
        border: "1px solid var(--cl-border, rgba(0,0,0,0.1))",
        borderRadius: 12,
        background: "var(--cl-card, #fff)",
        overflow: "hidden",
        ...style,
      },
    },
    children
  );
}
function CardHeader({ children, style, ...rest }) {
  return createElement(
    "div",
    {
      ...rest,
      style: {
        padding: "12px 14px",
        fontWeight: 600,
        borderBottom: "1px solid var(--cl-border, rgba(0,0,0,0.08))",
        ...style,
      },
    },
    children
  );
}
function CardBody({ children, style, ...rest }) {
  return createElement("div", { ...rest, style: { padding: 14, ...style } }, children);
}

function Pill({ children, tone, style, ...rest }) {
  const bg =
    tone === "info"
      ? "rgba(37,99,235,0.12)"
      : tone === "success"
        ? "rgba(22,163,74,0.12)"
        : tone === "warning"
          ? "rgba(217,119,6,0.14)"
          : "rgba(0,0,0,0.06)";
  return createElement(
    "span",
    {
      ...rest,
      style: {
        display: "inline-flex",
        alignItems: "center",
        padding: "2px 8px",
        borderRadius: 999,
        fontSize: 12,
        fontWeight: 600,
        background: bg,
        ...style,
      },
    },
    children
  );
}

function Badge(props) {
  return Pill(props);
}
function Chip(props) {
  return Pill(props);
}
function Tag(props) {
  return Pill(props);
}

function Callout({ children, title, tone, style, ...rest }) {
  const border =
    tone === "warning" ? "#d97706" : tone === "danger" ? "#b00020" : "#2563eb";
  return createElement(
    "div",
    {
      ...rest,
      style: {
        borderLeft: `4px solid ${border}`,
        background: "rgba(0,0,0,0.03)",
        borderRadius: 8,
        padding: "12px 14px",
        ...style,
      },
    },
    title ? createElement("div", { style: { fontWeight: 600, marginBottom: 6 } }, title) : null,
    children
  );
}

function Stat({ value, label, tone, style, ...rest }) {
  return createElement(
    "div",
    {
      ...rest,
      style: {
        border: "1px solid var(--cl-border, rgba(0,0,0,0.1))",
        borderRadius: 12,
        padding: 14,
        ...style,
      },
    },
    createElement("div", { style: { fontSize: 22, fontWeight: 700 } }, value),
    createElement("div", { style: { fontSize: 12, color: "var(--cl-muted,#6b7280)", marginTop: 4 } }, label)
  );
}

function Button({ children, style, ...rest }) {
  return createElement(
    "button",
    {
      type: "button",
      ...rest,
      style: {
        font: "inherit",
        padding: "6px 12px",
        borderRadius: 8,
        border: "1px solid var(--cl-border, rgba(0,0,0,0.15))",
        background: "var(--cl-card, #fff)",
        cursor: "pointer",
        ...style,
      },
    },
    children
  );
}

function Divider({ style, ...rest }) {
  return createElement("hr", {
    ...rest,
    style: { border: 0, borderTop: "1px solid var(--cl-border, rgba(0,0,0,0.1))", margin: "12px 0", ...style },
  });
}

function Spacer({ size = 12 }) {
  return createElement("div", { style: { height: typeof size === "number" ? size : 12 } });
}

function Link({ children, href, style, ...rest }) {
  return createElement("a", { href: href || "#", ...rest, style: { color: "#2563eb", ...style } }, children);
}

function Code({ children, style, ...rest }) {
  return createElement(
    "code",
    {
      ...rest,
      style: {
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize: 12,
        background: "rgba(0,0,0,0.05)",
        padding: "1px 4px",
        borderRadius: 4,
        ...style,
      },
    },
    children
  );
}

function Table({ children, style, ...rest }) {
  return createElement("table", { ...rest, style: { width: "100%", borderCollapse: "collapse", ...style } }, children);
}

function TextInput(props) {
  return createElement("input", { type: "text", ...props, style: { font: "inherit", padding: "6px 8px", borderRadius: 6, border: "1px solid #ccc", ...(props.style || {}) } });
}
function TextArea(props) {
  return createElement("textarea", { ...props, style: { font: "inherit", padding: 8, borderRadius: 6, border: "1px solid #ccc", width: "100%", ...(props.style || {}) } });
}
function Checkbox({ label, ...rest }) {
  return createElement("label", { style: { display: "inline-flex", gap: 6, alignItems: "center" } }, createElement("input", { type: "checkbox", ...rest }), label);
}
function Toggle(props) {
  return Checkbox(props);
}
function Select({ children, ...rest }) {
  return createElement("select", { ...rest, style: { font: "inherit", padding: 6, ...(rest.style || {}) } }, children);
}

function passthrough(name, tag = "div") {
  return function Stub(props) {
    const { children, style, ...rest } = props || {};
    return createElement(
      tag,
      {
        ...rest,
        "data-cl-stub": name,
        style: { ...style },
      },
      children
    );
  };
}

const stubs = {
  Badge,
  BarChart: passthrough("BarChart"),
  Button,
  Callout,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  Chip,
  Code,
  CollapsibleSection: passthrough("CollapsibleSection"),
  DiffStats: passthrough("DiffStats"),
  DiffView: passthrough("DiffView"),
  Divider,
  Grid,
  H1,
  H2,
  H3,
  IconButton: Button,
  LineChart: passthrough("LineChart"),
  Link,
  PieChart: passthrough("PieChart"),
  Pill,
  Row,
  Select,
  Spacer,
  Stack,
  Stat,
  Swatch: passthrough("Swatch"),
  Table,
  Tag,
  Text,
  TextArea,
  TextInput,
  TodoList: passthrough("TodoList"),
  TodoListCard: passthrough("TodoListCard"),
  Toggle,
  UsageBar: passthrough("UsageBar"),
  canvasPaletteDark: {},
  canvasPaletteLight: {},
  canvasTokens: {},
  canvasTokensLight: {},
  categoryPaletteDark: {},
  categoryPaletteLight: {},
  colorPalette: {},
  computeDAGLayout: () => ({}),
  mergeStyle: (a, b) => ({ ...(a || {}), ...(b || {}) }),
  usageColorSequence: [],
  useCanvasAction: () => () => {},
  useCanvasState: (init) => [typeof init === "function" ? init() : init, () => {}],
  useHostTheme: () => ({ kind: window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light" }),
};

function installGlobals() {
  globalThis.React = React;
  globalThis.ReactDOM = { render, createRoot(container) {
    return {
      render(v) {
        render(v, container);
      },
      unmount() {
        while (container.firstChild) container.removeChild(container.firstChild);
      },
    };
  } };
  for (const [k, v] of Object.entries(stubs)) {
    globalThis[k] = v;
  }
  // Banner so users know this is limited
  if (!document.getElementById("cl-minimal-runtime-banner")) {
    const b = document.createElement("div");
    b.id = "cl-minimal-runtime-banner";
    b.textContent = "Minimal open preview host — limited Cursor component fidelity";
    b.style.cssText =
      "position:sticky;top:0;z-index:9999;font:12px/1.3 -apple-system,BlinkMacSystemFont,sans-serif;" +
      "padding:6px 12px;background:#fff8e6;color:#92400e;border-bottom:1px solid #fcd34d";
    document.body.prepend(b);
  }
  const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.style.setProperty("--cl-muted", dark ? "#9ca3af" : "#6b7280");
  document.documentElement.style.setProperty("--cl-border", dark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.1)");
  document.documentElement.style.setProperty("--cl-card", dark ? "#252526" : "#ffffff");
}

/**
 * Cursor-compatible entry used by host.html
 * @param {string} moduleHref
 */
export async function mountCanvas(moduleHref) {
  installGlobals();
  const root = document.getElementById("root") || document.body;
  const mod = await import(moduleHref);
  const Comp = mod.default || mod.Canvas || mod.App;
  if (typeof Comp !== "function") {
    throw new Error(
      "Canvas module has no default export component (minimal host expects export default function …)"
    );
  }
  render(createElement(Comp, null), root);
}

export default { mountCanvas };
