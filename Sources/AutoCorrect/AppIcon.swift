import AppKit

/// A compact drawn mark: a lowercase a with a correction check.
/// The menu version is a template so macOS supplies the correct contrast.
enum AppIcon {
    static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 23, height: 20), flipped: false) { rect in
            drawMark(in: rect.insetBy(dx: 1, dy: 1), color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AutoCorrect"
        return image
    }

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
