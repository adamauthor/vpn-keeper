import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let n = CGFloat(pixels)
        let inset = n * 0.06
        let path = NSBezierPath(
            roundedRect: NSRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset), xRadius: n * 0.21,
            yRadius: n * 0.21)
        let gradient = NSGradient(
            starting: NSColor(red: 0.04, green: 0.58, blue: 0.57, alpha: 1),
            ending: NSColor(red: 0.02, green: 0.24, blue: 0.32, alpha: 1))!
        gradient.draw(in: path, angle: -90)
        // Original shield artwork; the app icon does not embed an SF Symbol.
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: n * 0.50, y: n * 0.82))
        shield.line(to: NSPoint(x: n * 0.75, y: n * 0.72))
        shield.line(to: NSPoint(x: n * 0.75, y: n * 0.49))
        shield.curve(
            to: NSPoint(x: n * 0.50, y: n * 0.20),
            controlPoint1: NSPoint(x: n * 0.75, y: n * 0.35),
            controlPoint2: NSPoint(x: n * 0.62, y: n * 0.25))
        shield.curve(
            to: NSPoint(x: n * 0.25, y: n * 0.49),
            controlPoint1: NSPoint(x: n * 0.38, y: n * 0.25),
            controlPoint2: NSPoint(x: n * 0.25, y: n * 0.35))
        shield.line(to: NSPoint(x: n * 0.25, y: n * 0.72))
        shield.close()
        NSColor.white.setFill()
        shield.fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: n * 0.37, y: n * 0.51))
        check.line(to: NSPoint(x: n * 0.46, y: n * 0.42))
        check.line(to: NSPoint(x: n * 0.64, y: n * 0.62))
        check.lineWidth = n * 0.055
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(red: 0.03, green: 0.37, blue: 0.40, alpha: 1).setStroke()
        check.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}

// ICNS accepts PNG payloads. Package them directly without relying on iconutil.
func uint32(_ value: Int) -> Data {
    var n = UInt32(value).bigEndian
    return withUnsafeBytes(of: &n) { Data($0) }
}
let entries = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]
var body = Data()
for (kind, name) in entries {
    let png = try Data(contentsOf: directory.appendingPathComponent(name))
    body.append(Data(kind.utf8))
    body.append(uint32(png.count + 8))
    body.append(png)
}
var file = Data("icns".utf8)
file.append(uint32(body.count + 8))
file.append(body)
try file.write(to: directory.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
