import Cocoa

// Draw in points so normal and Retina menus use the same silhouette.
func bitmap(scale: Int) -> NSBitmapImageRep {
    let pixels = 16 * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 16, height: 16)
    let context = CGContext(data: bitmap.bitmapData, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: bitmap.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setFillColor(NSColor.black.cgColor)
    let outline = CGMutablePath()
    for step in 0..<144 {
        let angle = Double(step) * .pi * 2 / 144
        let radius = 6.6 + 0.25 * cos(angle * 12)
        let point = CGPoint(x: 8 + radius * cos(angle), y: 8 + radius * sin(angle))
        if step == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
    }
    outline.closeSubpath()
    context.addPath(outline)
    context.fillPath()
    context.setBlendMode(.clear)
    // A bite and small transparent chips remain visible in either menu appearance.
    for (x, y, radius) in [(13.5, 13.0, 3.0), (5.0, 10.3, 1.0),
                            (9.0, 8.4, 1.05), (5.5, 5.0, 0.9), (11.1, 4.8, 0.8)] {
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
    return bitmap
}

let image = NSImage(size: NSSize(width: 16, height: 16))
for scale in [1, 2] { image.addRepresentation(bitmap(scale: scale)) }
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
if CommandLine.arguments.count > 2 {
    try bitmap(scale: 8).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
