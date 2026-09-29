// Run from the repository root:
// swiftc Sources/AutoCorrect/AppIcon.swift scripts/generate-icon.swift -o /tmp/autocorrect-icon
// /tmp/autocorrect-icon Resources/AppIcon.icns
import AppKit

@main
struct GenerateIcon {
    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconset = temporary.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Unable to create icon bitmap") }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                AppIcon.applicationImage(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
            }
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
        print("Created \(output)")
    }
}
