#!/usr/bin/env swift
//
//  make-icon.swift
//  Regenerates the AppIcon PNGs:  swift Tools/make-icon.swift
//
//  The icon is the app's idea in one picture: a display split 1 : 3 : 1,
//  with the middle zone lit.
//

import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                          ?? "tessellitas/Assets.xcassets/AppIcon.appiconset")

// MARK: - Geometry (1024-point design grid)

/// Apple's icon grid: an 824pt continuous-corner shape centred in a 1024pt canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)

/// A superellipse approximates the continuous corners of the macOS icon shape.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Three full-height tiles, 1 : 3 : 1, centred on the plate.
func tiles() -> [CGRect] {
    let width: CGFloat = 628, height: CGFloat = 272, gap: CGFloat = 22
    let unit = (width - 2 * gap) / 5
    let originX = plate.midX - width / 2
    let originY = plate.midY - height / 2
    var x = originX
    return [unit, unit * 3, unit].map { w in
        defer { x += w + gap }
        return CGRect(x: x, y: originY, width: w, height: height)
    }
}

// MARK: - Drawing

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func fillGradient(_ ctx: CGContext, path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(colors), start: from, end: to, options: [])
    ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
    let shape = squircle(in: plate)

    // Plate, with the soft drop shadow macOS icons carry.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xEEF0F4))
    ctx.fillPath()
    ctx.restoreGState()

    fillGradient(ctx, path: shape, colors: [color(0xFFFFFF), color(0xE3E6EC)],
                 from: CGPoint(x: 0, y: plate.maxY), to: CGPoint(x: 0, y: plate.minY))

    // Hairline highlight on the top edge, hairline shade on the bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.95), color(0x000000, 0.10)]),
                           start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    ctx.restoreGState()

    let rects = tiles()
    let radius: CGFloat = 34

    for (index, rect) in rects.enumerated() {
        let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let lit = index == 1

        // Shadow beneath each tile; the lit one glows blue.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: lit ? -16 : -6), blur: lit ? 36 : 12,
                      color: lit ? color(0x0A63F2, 0.38) : color(0x1C2333, 0.16))
        ctx.addPath(tile)
        ctx.setFillColor(lit ? color(0x1F7AFF) : color(0xBCC3D0))
        ctx.fillPath()
        ctx.restoreGState()

        fillGradient(ctx, path: tile,
                     colors: lit ? [color(0x5EB0FF), color(0x0A6BFF)] : [color(0xD3D8E2), color(0xB1B8C7)],
                     from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))

        // Soft top sheen so the tiles read as slightly raised.
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        ctx.drawLinearGradient(gradient([color(0xFFFFFF, lit ? 0.34 : 0.45), color(0xFFFFFF, 0)]),
                               start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.maxY - rect.height * 0.5), options: [])
        ctx.restoreGState()
    }
}

// MARK: - Export

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// (point size, scale) pairs required by the macOS AppIcon set.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []

for (points, scale) in slots {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try png(pixels: points * scale).write(to: outputDirectory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icons to \(outputDirectory.path)")
