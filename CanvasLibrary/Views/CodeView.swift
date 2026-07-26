//
//  CodeView.swift
//  TSXPretty
//

import AppKit
import SwiftUI

struct CodeView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let showLineNumbers: Bool
    let fontSize: Double
    let scrollToLine: Int?
    let contentID: UUID
    let backgroundColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        let textView = SelectableCodeTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = TSXHighlighter.Theme.current().plain
        textView.insertionPointColor = TSXHighlighter.Theme.current().plain
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            container.lineFragmentPadding = 4
        }
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        if showLineNumbers {
            let ruler = LineNumberRulerView(textView: textView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            context.coordinator.ruler = ruler
        }

        context.coordinator.textView = textView
        // Apply content immediately so the first paint is not blank.
        applyText(attributedText, to: textView, background: backgroundColor)
        context.coordinator.contentID = contentID
        context.coordinator.lastString = attributedText.string
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        scrollView.backgroundColor = backgroundColor
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true

        let needsTextUpdate =
            context.coordinator.contentID != contentID
            || context.coordinator.lastString != attributedText.string
            || textView.string.isEmpty && !attributedText.string.isEmpty

        if needsTextUpdate {
            context.coordinator.contentID = contentID
            context.coordinator.lastString = attributedText.string
            applyText(attributedText, to: textView, background: backgroundColor)
        }

        scrollView.rulersVisible = showLineNumbers
        if showLineNumbers {
            if scrollView.verticalRulerView == nil {
                let ruler = LineNumberRulerView(textView: textView)
                scrollView.verticalRulerView = ruler
                scrollView.hasVerticalRuler = true
                context.coordinator.ruler = ruler
            }
            context.coordinator.ruler?.needsDisplay = true
        }

        if let line = scrollToLine, line > 0, context.coordinator.lastScrolledLine != line {
            context.coordinator.lastScrolledLine = line
            scrollTo(line: line, in: textView)
        }
    }

    private func applyText(_ attributed: NSAttributedString, to textView: NSTextView, background: NSColor) {
        textView.textStorage?.setAttributedString(attributed)
        // Guarantee base visibility even if a run lacks a color attribute.
        if attributed.length == 0 {
            textView.string = ""
        }
        textView.backgroundColor = background
        textView.drawsBackground = true
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.needsDisplay = true
    }

    private func scrollTo(line: Int, in textView: NSTextView) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }
        var current = 1
        var index = 0
        while index < text.length && current < line {
            index = text.lineRange(for: NSRange(location: index, length: 0)).upperBound
            current += 1
        }
        let location = min(index, max(0, text.length - 1))
        let range = text.lineRange(for: NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        var lastScrolledLine: Int?
        var contentID: UUID?
        var lastString: String?
    }
}

/// NSTextView that stays selectable even when not first responder focus issues arise.
private final class SelectableCodeTextView: NSTextView {
    override func resignFirstResponder() -> Bool {
        // Keep selection visible when focus moves to the Preview/Source picker.
        let ok = super.resignFirstResponder()
        return ok
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

// MARK: - Line numbers

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
        textView.postsFrameChangedNotifications = true
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func textDidChange(_ note: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        let theme = TSXHighlighter.Theme.current(appearance: textView.effectiveAppearance)
        let bg = theme.background.blended(withFraction: 0.04, of: .black) ?? theme.background
        let fg = theme.comment
        bg.setFill()
        rect.fill()

        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        var lineNumber = 1
        let ns = textView.string as NSString
        let prefix = ns.substring(to: min(glyphRange.location, ns.length))
        lineNumber += prefix.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }

        var glyphIndex = glyphRange.location
        let end = NSMaxRange(glyphRange)

        while glyphIndex < end {
            var lineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let isLineStart = charIndex == 0 || ns.character(at: charIndex - 1) == 10

            if isLineStart {
                let frag = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let y = frag.origin.y + relativePoint.y
                let label = "\(lineNumber)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: fg,
                ]
                let size = label.size(withAttributes: attrs)
                let drawRect = NSRect(
                    x: ruleThickness - size.width - 8,
                    y: y + (frag.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                label.draw(in: drawRect, withAttributes: attrs)
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(lineRange)
        }
    }
}
