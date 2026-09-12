import AppKit
import WispCore

/// Draws the two things the notes body renders as marks rather than as
/// characters: horizontal rules, and list bullets.
///
/// Both use the same trick. The characters stay in storage — the file on
/// disk is plain markdown, `---` and `- ` — and the styling pass paints
/// them with a `.clear` foreground; this class then draws the mark over
/// the space they reserved. Layout is untouched, so wrapping, selection,
/// and every offset in the document are exactly what the plain text says
/// they are.
///
/// The rule spans the line fragment's full width, so it tracks panel
/// resizes for free.
final class NotesLayoutManager: NSLayoutManager {
    /// Stroke color for horizontal rules, refreshed on every theme flip
    /// via `applyPalette`.
    var ruleColor: NSColor = .secondaryLabelColor
    /// Bullets are drawn in the body text color, not the rule color: they
    /// are content, and a muted bullet reads as a disabled item.
    var bulletColor: NSColor = .textColor
    /// The body font at the current scale. Bullets are drawn at it so
    /// they track ⌘= / ⌘- with the text they lead.
    var bulletFont: NSFont = .systemFont(ofSize: Metrics.bodySize)
    /// Nesting is measured against the configured indent width, so a list
    /// typed with the user's own Tab key steps glyphs at the same rate it
    /// steps columns.
    var indentWidth: Int = Indent().width
    /// The indent unit as typed, for measuring where each nesting level's
    /// marker column lands.
    var indentUnit: String = Indent().unit
    /// Guides down the left of nested items, one per ancestor level, in
    /// the faintest text tier: they are structure, not content.
    var guideColor: NSColor = .separatorColor
    /// Raw mode draws neither rules nor bullets: both stand in for characters
    /// the styling pass hides, and in raw mode nothing is hidden.
    var isSourceView: Bool = false

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
            if SmartEditing.isHorizontalRuleLine(lineRange: lineRange, in: nsString) {
                drawRule(for: lineRange, at: origin, in: context)
            } else {
                drawGuides(for: lineRange, in: nsString, at: origin)
                if let item = SmartEditing.listItem(lineRange: lineRange, in: nsString) {
                    if case .task(let checked) = item.marker {
                        drawTaskBox(checked: checked, for: item, at: origin)
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

    /// Paints the bullet at the leading edge of the advance the hidden
    /// marker reserved, sitting on that line's baseline.
    ///
    /// Leading edge, not centered: the styling pass kerns every bullet
    /// marker out to exactly the glyph's own width, so the reserved box
    /// and the glyph are the same size and there is nothing to center.
    private func drawMarker(_ glyph: String, for item: SmartEditing.ListItem, at origin: NSPoint) {
        let glyphRange = self.glyphRange(
            forCharacterRange: item.markerRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let fragmentRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let markerRect = boundingRect(forGlyphRange: glyphRange, in: textContainers[0])
        // `location(forGlyphAt:)` is relative to the fragment's own origin,
        // and its `y` is the baseline — the one measurement that puts the
        // bullet on the text's line rather than in the middle of a
        // 1.45×-leaded box.
        let baseline = origin.y + fragmentRect.minY
            + location(forGlyphAt: glyphRange.location).y

        let glyph = NSAttributedString(
            string: glyph, attributes: [.font: bulletFont, .foregroundColor: bulletColor])
        glyph.draw(at: NSPoint(
            x: origin.x + markerRect.minX,
            // The text view is flipped, so `draw(at:)` takes the top-left
            // of the glyph's line box rather than its baseline.
            y: baseline - bulletFont.ascender))
    }

    // MARK: Indent guides

    /// A one-point line for each level a nested line hangs under, centred
    /// on that ancestor's own marker — bullet, box, or number — and
    /// running the full height of the line's paragraph, wrapped lines
    /// included, so consecutive lines join into one unbroken guide.
    /// Blank lines inside a list carry the guides across the gap (see
    /// `SmartEditing.guideDepth`).
    ///
    /// The first line under a parent starts its guide one cap height
    /// below the parent's marker centre — half a cap clear of the
    /// parent's letters, which end half a cap below that centre — rather
    /// than at its own fragment's top, which butts against the parent's
    /// descenders and reads as hanging off the marker. A line with no
    /// ancestor at some level — a hand-typed jump of two levels — falls
    /// back to where a marker at that level would sit, starting at its
    /// own ascender line.
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
            let ancestor = ancestors[level]
            let centre = ancestor.map { markerCentre(of: $0.item) }
                ?? fallbackMarkerCentre(level: level)
            let top: CGFloat
            if depthAbove > level {
                top = fragmentTop
            } else if let ancestor {
                top = origin.y + baseline(of: ancestor.item) + bulletFont.capHeight / 2
            } else {
                top = ascenderTop
            }
            NSRect(x: (origin.x + centre).rounded() - 0.5, y: top, width: 1, height: bottom - top)
                .fill()
        }
    }

    /// Container-relative y of the baseline an item's marker sits on.
    private func baseline(of item: SmartEditing.ListItem) -> CGFloat {
        let glyph = glyphRange(forCharacterRange: item.markerRange, actualCharacterRange: nil).location
        return lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            + location(forGlyphAt: glyph).y
    }

    /// Container-relative x of the middle of an item's marker. Bullets
    /// and boxes fill the width the marker is kerned to, and an ordered
    /// marker is the visible text, so the reserved rectangle's middle is
    /// the mark's middle in every case.
    private func markerCentre(of item: SmartEditing.ListItem) -> CGFloat {
        let glyphs = glyphRange(forCharacterRange: item.markerRange, actualCharacterRange: nil)
        return boundingRect(forGlyphRange: glyphs, in: textContainers[0]).midX
    }

    /// Where a bullet at `level` would sit: the leading whitespace is
    /// indented by its own width on top of rendering itself (see
    /// `styleLists`), so the marker column is twice the whitespace in.
    private func fallbackMarkerCentre(level: Int) -> CGFloat {
        let whitespace = NSAttributedString(
            string: String(repeating: indentUnit, count: level), attributes: [.font: bulletFont]
        ).size().width
        let bullet = NSAttributedString(
            string: SmartEditing.bulletGlyph(depth: 0), attributes: [.font: bulletFont]
        ).size().width
        return whitespace * 2 + bullet / 2
    }

    // MARK: Task boxes

    /// The side of a task's box, in points, for text set in `font`. The
    /// ascender rather than the cap height: the box is chrome standing in
    /// for text, and at cap height it reads as a small square beside the
    /// words rather than a control in front of them. Any bigger and it
    /// crowds the line above at the body's 1.35× leading.
    ///
    /// Drawn rather than typeset: `☐` and `☑` fall back to two different
    /// fonts on macOS — Apple Symbols and the system face — and come out
    /// at two different sizes, the empty box barely above the x-height.
    static func taskBoxSide(for font: NSFont) -> CGFloat {
        font.ascender.rounded()
    }

    /// The box, centred on the midpoint of the cap height so it sits with
    /// the letters rather than hanging off the baseline; the stroke sits
    /// inside the reserved width, so a box never touches the text after it.
    private func drawTaskBox(checked: Bool, for item: SmartEditing.ListItem, at origin: NSPoint) {
        let glyphRange = self.glyphRange(
            forCharacterRange: item.markerRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let fragmentRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let markerRect = boundingRect(forGlyphRange: glyphRange, in: textContainers[0])
        let baseline = origin.y + fragmentRect.minY
            + location(forGlyphAt: glyphRange.location).y

        let side = Self.taskBoxSide(for: bulletFont)
        // 1.5pt at the default size, stepping in halves with the scale.
        let stroke = max(1, (bulletFont.pointSize / 5).rounded() / 2)
        let inset = stroke / 2
        // Flipped view: `y` grows downward, so the top edge is the baseline
        // less the box's reach above the cap-height midpoint.
        let midline = baseline - bulletFont.capHeight / 2
        let box = NSRect(
            x: origin.x + markerRect.minX + inset, y: midline - side / 2 + inset,
            width: side - stroke, height: side - stroke)
        let radius = (side / 5).rounded()

        bulletColor.setStroke()
        let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        outline.stroke()

        guard checked else { return }
        // A tick from a third of the way across, down to the low point at
        // the middle, up to the top-right corner region.
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
