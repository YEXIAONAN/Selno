// Regenerate with: DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer xcrun swift Tools/GenerateAppIcon.swift
// Every output is rendered from these vector paths, never enlarged from a bitmap.
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Selno/Assets.xcassets/AppIcon.appiconset")
let branding = root.appendingPathComponent("Branding")
try FileManager.default.createDirectory(at: branding, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func render(pixels: Int) -> CGImage {
    // Small versions are supersampled directly from the vector master for crisp curves.
    let sample = pixels < 128 ? 8 : (pixels < 1024 ? 4 : 1)
    let size = pixels * sample
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    // Use top-left coordinates so the path is easy to tune and reproduce.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    let tile = CGMutablePath()
    let k: CGFloat = 0.55228475, r: CGFloat = 190
    tile.move(to: CGPoint(x: 274, y: 76))
    tile.addLine(to: CGPoint(x: 750, y: 76))
    tile.addCurve(to: CGPoint(x: 940, y: 266), control1: CGPoint(x: 750 + r * k, y: 76), control2: CGPoint(x: 940, y: 266 - r * k))
    tile.addLine(to: CGPoint(x: 940, y: 742))
    tile.addCurve(to: CGPoint(x: 750, y: 932), control1: CGPoint(x: 940, y: 742 + r * k), control2: CGPoint(x: 750 + r * k, y: 932))
    tile.addLine(to: CGPoint(x: 274, y: 932))
    tile.addCurve(to: CGPoint(x: 84, y: 742), control1: CGPoint(x: 274 - r * k, y: 932), control2: CGPoint(x: 84, y: 742 + r * k))
    tile.addLine(to: CGPoint(x: 84, y: 266))
    tile.addCurve(to: CGPoint(x: 274, y: 76), control1: CGPoint(x: 84, y: 266 - r * k), control2: CGPoint(x: 274 - r * k, y: 76))
    tile.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 13), blur: 24, color: color(0.16, 0.15, 0.14, 0.22))
    context.addPath(tile)
    context.setFillColor(color(0.92, 0.91, 0.89))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile); context.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [color(0.985, 0.979, 0.96), color(0.89, 0.885, 0.87)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 360, y: 76), end: CGPoint(x: 640, y: 950), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(1, 1, 1, 0.85)); context.setLineWidth(2); context.strokePath()

    // A single continuous S ribbon. Quiet horizontal shoulders suggest ordered rows,
    // while rounded turns and generous margins keep the mark calm at Dock sizes.
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 648, y: 326))
    mark.addCurve(to: CGPoint(x: 426, y: 316), control1: CGPoint(x: 590, y: 308), control2: CGPoint(x: 484, y: 308))
    mark.addCurve(to: CGPoint(x: 410, y: 464), control1: CGPoint(x: 328, y: 329), control2: CGPoint(x: 323, y: 426))
    mark.addLine(to: CGPoint(x: 602, y: 548))
    mark.addCurve(to: CGPoint(x: 598, y: 694), control1: CGPoint(x: 695, y: 589), control2: CGPoint(x: 688, y: 682))
    mark.addCurve(to: CGPoint(x: 376, y: 684), control1: CGPoint(x: 540, y: 702), control2: CGPoint(x: 434, y: 702))
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 3), blur: 2, color: color(0.16, 0.15, 0.14, 0.12))
    context.addPath(mark)
    context.setLineWidth(76); context.setLineCap(.round); context.setLineJoin(.round)
    context.setStrokeColor(color(0.205, 0.215, 0.213)); context.strokePath()
    context.restoreGState()
    let image = context.makeImage()!
    guard sample > 1 else { return image }
    let output = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    output.interpolationQuality = .high
    output.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return output.makeImage()!
}

func writePNG(pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: render(pixels: pixels))
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

try writePNG(pixels: 1024, to: branding.appendingPathComponent("SelnoIcon-1024.png"))
try writePNG(pixels: 4096, to: branding.appendingPathComponent("SelnoIcon-master-4096.png"))
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(pixels: points * scale, to: catalog.appendingPathComponent(name))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: catalog.appendingPathComponent("Contents.json"))
print("Rendered vector master (4096), primary icon (1024), and 10 macOS AppIcon slots.")
