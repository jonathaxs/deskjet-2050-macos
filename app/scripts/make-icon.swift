// Draws the app icon: a black pixel-art printer seen from the side, on a light tile.
// Run from app/: swift scripts/make-icon.swift
// Writes Resources/AppIcon.icns (for the app) and ../.github/appicons/deskjet2050-rounded.png (for the README).
import AppKit

let size = 32  // pixel-art grid
var grid = [[NSColor?]](repeating: [NSColor?](repeating: nil, count: size), count: size)

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
let body = hex(0x1c1c1e), seam = hex(0x070707), top = hex(0x3a3a3d), side = hex(0x2a2a2d)
let paper = hex(0xffffff), edge = hex(0x8e8e93), ink = hex(0xc7c7cc), led = hex(0x34c759)

let dy = 2  // moves the drawing down so it sits in the middle
func put(_ x: Int, _ y: Int, _ c: NSColor) {
    let y = y + dy
    if (0..<size).contains(x), (0..<size).contains(y) { grid[y][x] = c }
}
func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: NSColor) {
    for y in y0...y1 { for x in x0...x1 { put(x, y, c) } }
}

// Input tray at the back, leaning back, with a blank sheet in front of it.
for i in 0...10 {
    let y = 13 - i, s = i / 2
    if i <= 9 { put(6 - s, y, side); put(7 - s, y, body) }
    if i == 10 {
        rect(8 - s, y, 14 - s, y, edge)
    } else {
        rect(8 - s, y, 13 - s, y, paper)
        put(14 - s, y, edge)
    }
}

// Body, with rounded corners, a lighter top, the scanner lid seam and a side panel line.
rect(5, 14, 26, 24, body)
rect(6, 14, 25, 14, top)
rect(5, 15, 26, 15, side)
rect(5, 17, 26, 17, seam)
rect(24, 18, 24, 23, seam)
for (x, y) in [(5, 14), (26, 14), (5, 24), (26, 24)] { grid[y + dy][x] = nil }
put(25, 16, led)

// Output slot, printed sheet coming out on the tray.
rect(25, 20, 26, 20, seam)
rect(26, 21, 31, 21, edge)
rect(26, 22, 31, 22, paper)
put(28, 22, ink); put(29, 22, ink)
rect(25, 23, 31, 23, body)
put(31, 23, top)

// Feet.
rect(7, 25, 8, 25, seam)
rect(23, 25, 24, 25, seam)

/// Renders the tile and the printer. `inset` is the empty border around the tile (macOS icons keep one).
func render(pixels: Int, inset: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .none
    let p = CGFloat(pixels)
    let tile = CGRect(x: p * inset, y: p * inset, width: p * (1 - 2 * inset), height: p * (1 - 2 * inset))
    let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225,
                      transform: nil)

    if inset > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -p * 0.01), blur: p * 0.02,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path); ctx.setFillColor(.white); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [hex(0xffffff).cgColor, hex(0xd9dade).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY),
                           options: [])
    ctx.restoreGState()

    // Grid fills 78% of the tile; whole pixels so the edges stay sharp.
    let cell = (tile.width * 0.78 / CGFloat(size)).rounded(.down)
    let origin = CGPoint(x: (tile.midX - cell * CGFloat(size) / 2).rounded(),
                         y: (tile.midY - cell * CGFloat(size) / 2).rounded())
    for y in 0..<size {
        for x in 0..<size {
            guard let c = grid[y][x] else { continue }
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(size - 1 - y) * cell,
                            width: cell, height: cell))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(pixels: base, inset: 0.1), "\(iconset)/icon_\(base)x\(base).png")
    write(render(pixels: base * 2, inset: 0.1), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

write(render(pixels: 512, inset: 0), "../.github/appicons/deskjet2050-rounded.png")
print("Wrote Resources/AppIcon.icns and .github/appicons/deskjet2050-rounded.png")
