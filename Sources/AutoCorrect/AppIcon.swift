import AppKit
import CoreText

/// A compact drawn mark: a lowercase a with a correction check.
/// The menu version is a template so macOS supplies the correct contrast.
enum AppIcon {
    private static let compactMenuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 15, weight: .semibold) as CTFont
            var character: UniChar = 97
            var glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
                  let letter = CTFontCreatePathForGlyph(font, glyph, nil),
                  let context = NSGraphicsContext.current?.cgContext else { return false }
            let letterBounds = letter.boundingBoxOfPath
            let check = CGMutablePath()
            check.move(to: CGPoint(x: letterBounds.maxX + 1, y: letterBounds.minY + 3.8))
            check.addLine(to: CGPoint(x: letterBounds.maxX + 3.4, y: letterBounds.minY + 1.3))
            check.addLine(to: CGPoint(x: letterBounds.maxX + 8, y: letterBounds.maxY + 1.5))
            // Center the actual ink, including the stroke, rather than a font's line box.
            let ink = letterBounds.union(check.boundingBoxOfPath.insetBy(dx: -0.85, dy: -0.85))
            let scale = min(16 / ink.width, 11 / ink.height)
            context.saveGState()
            context.translateBy(x: rect.midX - ink.midX * scale, y: rect.midY - ink.midY * scale)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(letter); context.fillPath()
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.7); context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(check); context.strokePath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AutoCorrect"
        return image
    }()

    static func menuImage() -> NSImage { compactMenuImage }

    static func applicationImage(size: CGFloat = 128) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let tile = rect.insetBy(dx: size * 0.07, dy: size * 0.07)
            let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.2, yRadius: size * 0.2)
            NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.14, green: 0.31, blue: 0.82, alpha: 1))?.draw(in: path, angle: -75)
            drawMark(in: rect.insetBy(dx: size * 0.20, dy: size * 0.23), color: .white)
            return true
        }
    }

    private static func drawMark(in rect: NSRect, color: NSColor) {
        let font = NSFont.systemFont(ofSize: rect.height * 1.02, weight: .semibold)
        ("a" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY - rect.height * 0.17), withAttributes: [.font: font, .foregroundColor: color])
        color.setStroke()
        let check = NSBezierPath()
        check.lineWidth = max(1.6, rect.height * 0.105)
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: rect.minX + rect.width * 0.54, y: rect.minY + rect.height * 0.39))
        check.line(to: NSPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.22))
        check.line(to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.69))
        check.stroke()
    }
}
