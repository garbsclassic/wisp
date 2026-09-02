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

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage,
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
            } else if let item = SmartEditing.listItem(lineRange: lineRange, in: nsString),
                      item.marker == .bullet {
                drawBullet(for: item, at: origin)
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
    private func drawBullet(for item: SmartEditing.ListItem, at origin: NSPoint) {
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
            string: SmartEditing.bulletGlyph(depth: item.depth(indentWidth: indentWidth)),
            attributes: [.font: bulletFont, .foregroundColor: bulletColor])
        glyph.draw(at: NSPoint(
            x: origin.x + markerRect.minX,
            // The text view is flipped, so `draw(at:)` takes the top-left
            // of the glyph's line box rather than its baseline.
            y: baseline - bulletFont.ascender))
    }
}
