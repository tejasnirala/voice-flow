// Renders Resources/AppIcon.icns (a white microphone on a blue→indigo rounded square). Run once when the design changes:
//   swiftc scripts/assets/make-icon.swift -o /tmp/make-icon && /tmp/make-icon build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let size = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.36, green: 0.25, blue: 0.85, alpha: 1))!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let m = mic.size
        mic.draw(in: NSRect(x: (s - m.width) / 2, y: (s - m.height) / 2, width: m.width, height: m.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
