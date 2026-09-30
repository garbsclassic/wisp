import AppKit
import WispCore

extension NSAttributedString.Key {
    /// Set by the styling pass on a line that is a thematic break, so drawing needn't work out
    /// again which `---` lines are rules and which underline a heading.
    static let horizontalRule = NSAttributedString.Key("WispHorizontalRule")
}

/// Draws rules, bullets, and checklist boxes over characters the styling pass paints clear, so
/// the file stays plain Markdown and layout, selection, and offsets match the text.
final class NotesLayoutManager: NSLayoutManager {
    /// Refreshed on every theme change by `MinimalTextEditor.restyle`.
    var ruleColor: NSColor = .secondaryLabelColor
    /// Body colour, since a muted bullet reads as a disabled item.
    var bulletColor: NSColor = .textColor
    /// At the current scale, so bullets track ⌘= and ⌘-.
    var bulletFont: NSFont = .systemFont(ofSize: Metrics.bodySize)
    /// So glyphs step at the same rate as the user's Tab indents.
    var indentWidth: Int = Indent().width
    /// For where each level's marker column lands.
    var indentUnit: String = Indent().unit
    /// The faintest tier: guides are structure, not content.
    var guideColor: NSColor = .separatorColor
    /// Raw mode hides nothing, so nothing is drawn over.
    var isSourceView: Bool = false
    /// A hairline, or a book's `*  *  *`.
    var ruleStyle: RuleStyle = .line
    /// A text tier, since thin strokes in `rule` vanish on light.
    var seamColor: NSColor = .tertiaryLabelColor

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // MARK: Whole-point line fragments

    /// The trailing empty line bypasses the delegate, so it's rounded here.
    override func setExtraLineFragmentRect(
        _ fragmentRect: NSRect, usedRect: NSRect, textContainer container: NSTextContainer
    ) {
        var fragment = fragmentRect
        var used = usedRect
        fragment.size.height = fragment.height.rounded()
        used.size.height = fragment.height
        super.setExtraLineFragmentRect(fragment, usedRect: used, textContainer: container)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard !isSourceView,
              let textStorage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let nsString = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        var lineStart = charRange.location
        let charEnd = charRange.location + charRange.length
        while lineStart < charEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            if lineRange.length > 0,
                textStorage.attribute(.horizontalRule, at: lineRange.location, effectiveRange: nil)
                    != nil
            {
                drawRule(for: lineRange, at: origin, in: context)
            } else {
                drawGuides(for: lineRange, in: nsString, at: origin)
                if let item = SmartEditing.listItem(lineRange: lineRange, in: nsString) {
                    if case .checklist(let checked) = item.marker {
                        drawChecklistBox(checked: checked, for: item, at: origin)
                    } else if let glyph = item.glyph(indentWidth: indentWidth) {
                        drawMarker(glyph, for: item, at: origin)
                    }
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    private func drawRule(for lineRange: NSRange, at origin: NSPoint, in context: CGContext) {
        let glyphRange = self.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let fragmentRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let cy = origin.y + fragmentRect.midY
        if ruleStyle == .seam {
            drawSeam(in: fragmentRect, centreY: cy, originX: origin.x)
            return
        }
        let lineRect = CGRect(
            x: origin.x + fragmentRect.minX,
            y: cy - 0.5,
            width: fragmentRect.width,
            height: 1.0
        )
        context.saveGState()
        context.setFillColor(ruleColor.cgColor)
        context.fill(lineRect)
        context.restoreGState()
    }

    /// Three asterisks an em apart, centred on their ink rather than their baseline, since the
    /// glyph sits at cap height.
    private func drawSeam(in fragmentRect: NSRect, centreY: CGFloat, originX: CGFloat) {
        let seam = NSMutableAttributedString(
            string: "***", attributes: [.font: bulletFont, .foregroundColor: seamColor])
        // Kerned after the first two, so the group stays centred.
        seam.addAttribute(.kern, value: bulletFont.pointSize, range: NSRange(location: 0, length: 2))

        var glyph = CGGlyph(0)
        var asterisk = unichar(0x2A)
        CTFontGetGlyphsForCharacters(bulletFont, &asterisk, &glyph, 1)
        let ink = bulletFont.boundingRect(forCGGlyph: glyph)
        // Flipped: ink above the baseline is at smaller y.
        let baseline = centreY + ink.midY

        let width = seam.size().width
        seam.draw(at: NSPoint(
            x: originX + fragmentRect.minX + ((fragmentRect.width - width) / 2).rounded(),
            y: baseline - bulletFont.ascender))
    }

    /// At the hidden marker's leading edge; its advance is kerned to the glyph's own width.
    private func drawMarker(_ glyph: String, for item: SmartEditing.ListItem, at origin: NSPoint) {
        guard let marker = marker(of: item) else { return }
        let glyph = NSAttributedString(
            string: glyph, attributes: [.font: bulletFont, .foregroundColor: bulletColor])
        glyph.draw(at: NSPoint(
            x: origin.x + marker.rect.minX,
            // Flipped, so `draw(at:)` takes the line box's top-left, not the baseline.
            y: origin.y + marker.baseline - bulletFont.ascender))
    }

    /// The hidden marker's rect and baseline, container-relative. `location(forGlyphAt:)`'s `y`
    /// is the baseline, which puts a mark on the text's line rather than mid-box.
    private func marker(of item: SmartEditing.ListItem) -> (rect: NSRect, baseline: CGFloat)? {
        let glyphs = glyphRange(forCharacterRange: item.markerRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        return (
            boundingRect(forGlyphRange: glyphs, in: textContainers[0]),
            fragment.minY + location(forGlyphAt: glyphs.location).y
        )
    }

    // MARK: Indent guides

    /// A guide per ancestor level, centred on its marker and running the line's full height so
    /// lines join. Under a parent it starts a cap height below the marker's centre, clear of the
    /// letters; with no ancestor it falls back to where a marker would sit.
    private func drawGuides(for lineRange: NSRange, in text: NSString, at origin: NSPoint) {
        guard let depth = SmartEditing.guideDepth(
                lineRange: lineRange, in: text, indentWidth: indentWidth), depth > 0
        else { return }
        let glyphRange = self.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let first = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let last = lineFragmentRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange: nil)
        let fragmentTop = origin.y + first.minY
        let ascenderTop = fragmentTop + location(forGlyphAt: glyphRange.location).y
            - bulletFont.ascender
        let bottom = origin.y + last.maxY

        let depthAbove: Int
        if lineRange.location > 0 {
            depthAbove = SmartEditing.guideDepth(
                lineRange: LineEdits.lineRange(in: text, at: lineRange.location - 1), in: text,
                indentWidth: indentWidth) ?? 0
        } else {
            depthAbove = 0
        }
        let ancestors = SmartEditing.ancestors(
            of: lineRange, depth: depth, in: text, indentWidth: indentWidth)

        guideColor.setFill()
        for level in 0..<depth {
            let ancestor = ancestors[level].flatMap { marker(of: $0.item) }
            let centre = ancestor?.rect.midX ?? fallbackMarkerCentre(level: level)
            let top: CGFloat
            if depthAbove > level {
                top = fragmentTop
            } else if let ancestor {
                top = origin.y + ancestor.baseline + bulletFont.capHeight / 2
            } else {
                top = ascenderTop
            }
            NSRect(x: (origin.x + centre).rounded() - 0.5, y: top, width: 1, height: bottom - top)
                .fill()
        }
    }

    /// Twice the whitespace in, since `styleLists` also indents a line by its whitespace's width.
    private func fallbackMarkerCentre(level: Int) -> CGFloat {
        let whitespace = NSAttributedString(
            string: String(repeating: indentUnit, count: level), attributes: [.font: bulletFont]
        ).size().width
        let bullet = NSAttributedString(
            string: SmartEditing.bulletGlyph(depth: 0), attributes: [.font: bulletFont]
        ).size().width
        return whitespace * 2 + bullet / 2
    }

    // MARK: Checklist boxes

    /// The ascender, not the cap height, so the box reads as a control rather than a small square.
    /// Drawn rather than typeset, since `☐` and `☑` fall back to different fonts and sizes.
    static func checklistBoxSide(for font: NSFont) -> CGFloat {
        font.ascender.rounded()
    }

    /// Centred on the cap-height midpoint, with the stroke inside the reserved width.
    private func drawChecklistBox(checked: Bool, for item: SmartEditing.ListItem, at origin: NSPoint) {
        guard let marker = marker(of: item) else { return }
        let baseline = origin.y + marker.baseline

        let side = Self.checklistBoxSide(for: bulletFont)
        // 1.5pt at the default size, stepping in halves with the scale.
        let stroke = max(1, (bulletFont.pointSize / 5).rounded() / 2)
        let inset = stroke / 2
        // Flipped, so `y` grows downward.
        let midline = baseline - bulletFont.capHeight / 2
        let box = NSRect(
            x: origin.x + marker.rect.minX + inset, y: midline - side / 2 + inset,
            width: side - stroke, height: side - stroke)
        let radius = (side / 5).rounded()

        bulletColor.setStroke()
        let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        outline.stroke()

        guard checked else { return }
        let tick = NSBezierPath()
        tick.lineWidth = stroke * 1.5
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        tick.move(to: NSPoint(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.52))
        tick.line(to: NSPoint(x: box.minX + box.width * 0.43, y: box.minY + box.height * 0.72))
        tick.line(to: NSPoint(x: box.minX + box.width * 0.77, y: box.minY + box.height * 0.30))
        tick.stroke()
    }
}

extension NotesLayoutManager: NSLayoutManagerDelegate {
    /// Whole-point fragments: at a fractional height the selection fill and its invalidated rect
    /// round differently and leave a painted row. The delegate rather than the setter, since the
    /// typesetter places the next line from this hook's rect.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let height = lineFragmentRect.pointee.height.rounded()
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        return true
    }
}
