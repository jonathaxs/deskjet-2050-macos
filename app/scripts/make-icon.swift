// Draws the app icon: a pixel-art printer seen from the side. Two looks: a black printer on a light tile,
// and a white printer on a dark tile (dark mode; tinted mode starts from this one).
// Run from app/: swift scripts/make-icon.swift (needs Xcode for actool).
// Writes:
//   Resources/AppIcon.icns              light icon, for macOS 14 and 15
//   Resources/AppIcon.icon              Icon Composer source with the light, dark and tinted looks
//   Resources/Assets.car                that icon compiled, for macOS 26 and later
//   Resources/PrinterIcon-*.png         the tile shown next to the printer name in the app
//   ../.github/appicons/deskjet2050-rounded.png   for the README
import AppKit

let size = 32  // pixel-art grid

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

struct Look {
    let body, seam, top, side, paper, edge, ink: NSColor
    let tile: (NSColor, NSColor)  // gradient, top to bottom
}
let led = hex(0x34c759)
let light = Look(body: hex(0x1c1c1e), seam: hex(0x070707), top: hex(0x3a3a3d), side: hex(0x2a2a2d),
                 paper: hex(0xffffff), edge: hex(0x8e8e93), ink: hex(0xc7c7cc),
                 tile: (hex(0xffffff), hex(0xd9dade)))
let dark = Look(body: hex(0xc7c7cc), seam: hex(0x7c7c80), top: hex(0xe5e5ea), side: hex(0xaeaeb2),
                paper: hex(0xffffff), edge: hex(0x636366), ink: hex(0x48484a),
                tile: (hex(0x2e2e30), hex(0x161618)))

func printer(_ k: Look) -> [[NSColor?]] {
    var grid = [[NSColor?]](repeating: [NSColor?](repeating: nil, count: size), count: size)
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
        if i <= 9 { put(6 - s, y, k.side); put(7 - s, y, k.body) }
        if i == 10 {
            rect(8 - s, y, 14 - s, y, k.edge)
        } else {
            rect(8 - s, y, 13 - s, y, k.paper)
            put(14 - s, y, k.edge)
        }
    }

    // Body, with rounded corners, a lighter top, the scanner lid seam and a side panel line.
    rect(5, 14, 26, 24, k.body)
    rect(6, 14, 25, 14, k.top)
    rect(5, 15, 26, 15, k.side)
    rect(5, 17, 26, 17, k.seam)
    rect(24, 18, 24, 23, k.seam)
    for (x, y) in [(5, 14), (26, 14), (5, 24), (26, 24)] { grid[y + dy][x] = nil }
    put(25, 16, led)

    // Output slot, printed sheet coming out on the tray.
    rect(25, 20, 26, 20, k.seam)
    rect(26, 21, 31, 21, k.edge)
    rect(26, 22, 31, 22, k.paper)
    put(28, 22, k.ink); put(29, 22, k.ink)
    rect(25, 23, 31, 23, k.body)
    put(31, 23, k.top)

    // Feet.
    rect(7, 25, 8, 25, k.seam)
    rect(23, 25, 24, 25, k.seam)
    return grid
}

/// Renders the printer, on its tile unless `tile` is false. `inset` is the empty border around the tile
/// (macOS icons keep one).
func render(_ k: Look, pixels: Int, inset: CGFloat, tile drawTile: Bool = true) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .none
    let p = CGFloat(pixels)
    let tile = CGRect(x: p * inset, y: p * inset, width: p * (1 - 2 * inset), height: p * (1 - 2 * inset))

    if drawTile {
        let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225,
                          transform: nil)
        if inset > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -p * 0.01), blur: p * 0.02,
                          color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.addPath(path); ctx.setFillColor(k.tile.1.cgColor); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [k.tile.0.cgColor, k.tile.1.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY),
                               options: [])
        ctx.restoreGState()
    }

    // Grid fills 78% of the tile; whole pixels so the edges stay sharp.
    let grid = printer(k)
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

func run(_ tool: String, _ args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [tool] + args
    try! process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0, "\(tool) failed")
}

let fm = FileManager.default

// Classic .icns, light look only.
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(light, pixels: base, inset: 0.1), "\(iconset)/icon_\(base)x\(base).png")
    write(render(light, pixels: base * 2, inset: 0.1), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
run("iconutil", ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"])

// Icon Composer file: the system draws the tile. The black printer shows in light mode, the white one in
// dark and tinted mode.
let icon = "Resources/AppIcon.icon"
try? fm.removeItem(atPath: icon)
try! fm.createDirectory(atPath: "\(icon)/Assets", withIntermediateDirectories: true)
write(render(light, pixels: 1024, inset: 0, tile: false), "\(icon)/Assets/printer-light.png")
write(render(dark, pixels: 1024, inset: 0, tile: false), "\(icon)/Assets/printer-dark.png")
let json = """
{
  "fill-specializations" : [
    { "value" : { "linear-gradient" : [ "srgb:1.00000,1.00000,1.00000,1.00000", "srgb:0.85098,0.85490,0.87059,1.00000" ] } },
    { "appearance" : "dark", "value" : { "linear-gradient" : [ "srgb:0.18039,0.18039,0.18824,1.00000", "srgb:0.08627,0.08627,0.09412,1.00000" ] } }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "printer-light.png",
          "name" : "printer-light",
          "hidden-specializations" : [ { "value" : false }, { "appearance" : "dark", "value" : true }, { "appearance" : "tinted", "value" : true } ]
        },
        {
          "image-name" : "printer-dark.png",
          "name" : "printer-dark",
          "hidden-specializations" : [ { "value" : true }, { "appearance" : "dark", "value" : false }, { "appearance" : "tinted", "value" : false } ]
        }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
"""
try! json.write(toFile: "\(icon)/icon.json", atomically: true, encoding: .utf8)

let car = NSTemporaryDirectory() + "AppIconCar"
try? fm.removeItem(atPath: car)
try! fm.createDirectory(atPath: car, withIntermediateDirectories: true)
run("actool", ["--compile", car, "--platform", "macosx", "--minimum-deployment-target", "26.0",
               "--app-icon", "AppIcon", "--output-partial-info-plist", car + "/partial.plist", icon])
try? fm.removeItem(atPath: "Resources/Assets.car")
try! fm.copyItem(atPath: car + "/Assets.car", toPath: "Resources/Assets.car")

// Tiles for the app window, 42 points at 2x so each grid pixel lands on whole screen pixels.
write(render(light, pixels: 84, inset: 0), "Resources/PrinterIcon-light.png")
write(render(dark, pixels: 84, inset: 0), "Resources/PrinterIcon-dark.png")

write(render(light, pixels: 512, inset: 0), "../.github/appicons/deskjet2050-rounded.png")
print("Wrote the app icons")
