import AppKit
import Foundation

// Turn assets/logo.jpg into a square app icon. White around the artwork is
// removed from the edges only, so the white Finder face stays.

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make-icon input.jpg output.png\n", stderr)
    exit(1)
}

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

guard let image = NSImage(contentsOf: URL(fileURLWithPath: input)) else {
    fputs("could not read \(input)\n", stderr)
    exit(1)
}

let sourceSize = image.size
let width = Int(sourceSize.width)
let height = Int(sourceSize.height)

func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    )
}

guard let color = bitmap(width: width, height: height), let pixels = color.bitmapData else {
    fputs("could not allocate bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: color)
NSColor.clear.set()
NSRect(x: 0, y: 0, width: width, height: height).fill()
image.draw(
    in: NSRect(x: 0, y: 0, width: width, height: height),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

let rowBytes = color.bytesPerRow

func isBackground(_ x: Int, _ y: Int) -> Bool {
    let index = y * rowBytes + x * 4
    return pixels[index] > 246 && pixels[index + 1] > 246 && pixels[index + 2] > 246
}

var seen = [Bool](repeating: false, count: width * height)
var queue: [(Int, Int)] = []
func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, y >= 0, x < width, y < height else { return }
    let slot = y * width + x
    if seen[slot] || !isBackground(x, y) { return }
    seen[slot] = true
    queue.append((x, y))
}

for x in 0..<width {
    enqueue(x, 0)
    enqueue(x, height - 1)
}
for y in 0..<height {
    enqueue(0, y)
    enqueue(width - 1, y)
}

var cursor = 0
while cursor < queue.count {
    let (x, y) = queue[cursor]
    cursor += 1
    pixels[y * rowBytes + x * 4 + 3] = 0
    enqueue(x + 1, y)
    enqueue(x - 1, y)
    enqueue(x, y + 1)
    enqueue(x, y - 1)
}

var minX = width
var minY = height
var maxX = 0
var maxY = 0
for y in 0..<height {
    for x in 0..<width where pixels[y * rowBytes + x * 4 + 3] > 20 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}

guard minX <= maxX, minY <= maxY else {
    fputs("logo had no artwork\n", stderr)
    exit(1)
}

let side = 1024
guard let canvas = bitmap(width: side, height: side) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
NSColor.clear.set()
NSRect(x: 0, y: 0, width: side, height: side).fill()
if let context = NSGraphicsContext.current?.cgContext {
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)
}
let artworkWidth = CGFloat(maxX - minX + 1)
let artworkHeight = CGFloat(maxY - minY + 1)
let margin = CGFloat(side) * 0.08
let scale = min((CGFloat(side) - margin * 2) / artworkWidth, (CGFloat(side) - margin * 2) / artworkHeight)
let drawnWidth = artworkWidth * scale
let drawnHeight = artworkHeight * scale
let origin = NSPoint(x: (CGFloat(side) - drawnWidth) / 2, y: (CGFloat(side) - drawnHeight) / 2)
let sourceRect = NSRect(x: minX, y: minY, width: Int(artworkWidth), height: Int(artworkHeight))
NSImage(cgImage: color.cgImage!, size: NSSize(width: width, height: height)).draw(
    in: NSRect(origin: origin, size: NSSize(width: drawnWidth, height: drawnHeight)),
    from: sourceRect,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = canvas.representation(using: .png, properties: [:]) else {
    fputs("could not encode png\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
