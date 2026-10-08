import AppKit

let destination = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let side = CGFloat(pixels)
        let inset = side * 0.08
        let rectangle = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        NSColor(calibratedRed: 0.15, green: 0.30, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: rectangle, xRadius: side * 0.19, yRadius: side * 0.19).fill()
        for (index, center) in [0.62, 0.39, 0.55].enumerated() {
            let x = side * (0.31 + Double(index) * 0.19)
            NSColor.white.withAlphaComponent(0.45).setStroke()
            let track = NSBezierPath()
            track.lineWidth = side * 0.035
            track.lineCapStyle = .round
            track.move(to: NSPoint(x: x, y: side * 0.26))
            track.line(to: NSPoint(x: x, y: side * 0.74))
            track.stroke()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - side * 0.065, y: side * center - side * 0.047, width: side * 0.13, height: side * 0.094), xRadius: side * 0.025, yRadius: side * 0.025).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    }
}

// ICNS supports PNG chunks directly. Building the container here also works
// when iconutil's ImageIO conversion service is unavailable in a sandbox.
let representations = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
func bigEndian(_ number: UInt32) -> Data {
    var value = number.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (type, name) in representations {
    let png = try Data(contentsOf: URL(fileURLWithPath: destination).appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(UInt32(png.count + 8)))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(chunks.count + 8)))
icon.append(chunks)
let iconPath = URL(fileURLWithPath: destination).deletingPathExtension().appendingPathExtension("icns")
try icon.write(to: iconPath)
print("Created \(iconPath.path)")
