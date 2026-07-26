/**
 * Canvas Library — Unlock Preview design mode.
 * Click text in the rendered canvas to edit; changes are sent to the host
 * as { oldText, newText } so the TSX source can be updated.
 */
(function () {
  const STYLE_ID = "cs-design-mode-style";
  const ATTR = "data-cs-editable";
  const ORIG = "data-cs-original";
  const EDITING = "data-cs-editing";

  let enabled = false;
  let activeEl = null;

  function post(name, payload) {
    try {
      window.webkit?.messageHandlers?.[name]?.postMessage(payload);
    } catch (_) {}
  }

  function ensureStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const s = document.createElement("style");
    s.id = STYLE_ID;
    s.textContent = `
      html.cs-design-mode, html.cs-design-mode body {
        cursor: default;
      }
      html.cs-design-mode [${ATTR}] {
        outline: 1px dashed transparent;
        outline-offset: 2px;
        border-radius: 3px;
        transition: outline-color 0.12s ease, background 0.12s ease;
        cursor: text;
      }
      html.cs-design-mode [${ATTR}]:hover {
        outline-color: rgba(59, 130, 246, 0.7);
        background: rgba(59, 130, 246, 0.06);
      }
      html.cs-design-mode [${ATTR}][${EDITING}] {
        outline: 2px solid rgba(59, 130, 246, 0.95);
        background: rgba(59, 130, 246, 0.08);
        min-width: 1ch;
      }
      #cs-design-banner {
        position: fixed;
        top: 0; left: 0; right: 0;
        z-index: 2147483646;
        font: 600 12px/1.3 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        padding: 8px 14px;
        background: rgba(37, 99, 235, 0.95);
        color: #fff;
        letter-spacing: 0.01em;
        box-shadow: 0 1px 0 rgba(0,0,0,0.08);
        display: none;
      }
      html.cs-design-mode #cs-design-banner { display: block; }
      html.cs-design-mode #root { padding-top: 36px; }
    `;
    document.head.appendChild(s);
  }

  function ensureBanner() {
    if (document.getElementById("cs-design-banner")) return;
    const b = document.createElement("div");
    b.id = "cs-design-banner";
    b.textContent =
      "Preview unlocked — click text to edit · Esc cancels field · changes write to source";
    document.body.prepend(b);
  }

  function isSkippable(el) {
    if (!el || el.nodeType !== 1) return true;
    const tag = el.tagName;
    if (["SCRIPT", "STYLE", "SVG", "PATH", "TEXTAREA", "INPUT", "SELECT", "BUTTON", "A"].includes(tag)) {
      // Allow BUTTON/A only if pure text label? skip for v1 safety
      return true;
    }
    if (el.closest("#cs-design-banner")) return true;
    if (el.id === "boot-error") return true;
    return false;
  }

  function directText(el) {
    let t = "";
    for (const n of el.childNodes) {
      if (n.nodeType === 3) t += n.textContent;
      else if (n.nodeType === 1) return null; // has element children
    }
    return t;
  }

  function markEditables(root) {
    clearMarks(root);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
    const candidates = [];
    while (walker.nextNode()) {
      const el = walker.currentNode;
      if (isSkippable(el)) continue;
      const text = directText(el);
      if (text === null) continue;
      const trimmed = text.trim();
      if (trimmed.length < 1) continue;
      if (trimmed.length > 500) continue;
      // Skip pure numbers that are only layout (optional) — keep stats
      candidates.push(el);
    }
    for (const el of candidates) {
      el.setAttribute(ATTR, "1");
      el.setAttribute(ORIG, el.textContent);
    }
  }

  function clearMarks(root) {
    finishEdit(false);
    (root || document).querySelectorAll(`[${ATTR}]`).forEach((el) => {
      el.removeAttribute(ATTR);
      el.removeAttribute(ORIG);
      el.removeAttribute(EDITING);
      el.contentEditable = "false";
      el.removeAttribute("contenteditable");
    });
  }

  function finishEdit(commit) {
    if (!activeEl) return;
    const el = activeEl;
    activeEl = null;
    el.removeAttribute(EDITING);
    el.contentEditable = "false";
    el.removeAttribute("contenteditable");

    const original = el.getAttribute(ORIG) ?? "";
    const next = el.textContent ?? "";
    if (!commit) {
      el.textContent = original;
      return;
    }
    if (next === original) return;
    // Keep DOM showing new text; host will recompile shortly
    el.setAttribute(ORIG, next);
    post("designEdit", {
      oldText: original,
      newText: next,
    });
  }

  function beginEdit(el) {
    if (!enabled || !el || !el.hasAttribute(ATTR)) return;
    if (activeEl && activeEl !== el) finishEdit(true);
    activeEl = el;
    el.setAttribute(EDITING, "1");
    el.contentEditable = "true";
    el.focus();
    // Select all for quick replace
    try {
      const range = document.createRange();
      range.selectNodeContents(el);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    } catch (_) {}
  }

  function onClick(e) {
    if (!enabled) return;
    const el = e.target?.closest?.(`[${ATTR}]`);
    if (!el) {
      if (activeEl) finishEdit(true);
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    beginEdit(el);
  }

  function onKeyDown(e) {
    if (!enabled || !activeEl) return;
    if (e.key === "Escape") {
      e.preventDefault();
      finishEdit(false);
    } else if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      finishEdit(true);
    }
  }

  function onFocusOut(e) {
    if (!enabled || !activeEl) return;
    // Defer so click on another editable can switch
    setTimeout(() => {
      if (!activeEl) return;
      if (document.activeElement === activeEl) return;
      if (activeEl.contains(document.activeElement)) return;
      finishEdit(true);
    }, 0);
  }

  window.CanvasLibraryDesign = {
    setEnabled(on) {
      ensureStyles();
      ensureBanner();
      enabled = !!on;
      document.documentElement.classList.toggle("cs-design-mode", enabled);
      const root = document.getElementById("root") || document.body;
      if (enabled) {
        markEditables(root);
        document.addEventListener("click", onClick, true);
        document.addEventListener("keydown", onKeyDown, true);
        document.addEventListener("focusout", onFocusOut, true);
      } else {
        document.removeEventListener("click", onClick, true);
        document.removeEventListener("keydown", onKeyDown, true);
        document.removeEventListener("focusout", onFocusOut, true);
        clearMarks(root);
      }
      post("designMode", { enabled });
    },
    refresh() {
      if (!enabled) return;
      const root = document.getElementById("root") || document.body;
      markEditables(root);
    },
    isEnabled() {
      return enabled;
    },
  };
})();
