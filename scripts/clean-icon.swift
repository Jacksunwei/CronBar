#!/usr/bin/env swift
import AppKit
import Foundation

// Takes a flattened icon image whose transparency was baked into a checkerboard
// (e.g. exported as JPG), detects the colored squircle by chroma, masks to a
// rounded rect, and re-exports a transparent PNG.
//
// Usage: clean-icon.swift <input> <output.png>

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: clean-icon.swift <input> <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

guard let img = NSImage(contentsOfFile: inPath),
      let tiff = img.tiffRepresentation,
      let src = NSBitmapImageRep(data: tiff) else {
    fatalError("could not load \(inPath)")
}

let w = src.pixelsWide
let h = src.pixelsHigh

// Redraw into a known RGBA8 buffer we can read directly (origin bottom-left).
let scan = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
)!
do {
    let ctx = NSGraphicsContext(bitmapImageRep: scan)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
}

// Find the bounding box of "colored" (saturated) pixels — the purple squircle.
// The checkerboard, white gloss edges, and gray drop shadow are all near-neutral.
let data = scan.bitmapData!
let chromaThreshold = 45
var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    let row = y * w * 4
    for x in 0..<w {
        let o = row + x * 4
        let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
        let chroma = max(r, max(g, b)) - min(r, min(g, b))
        if chroma > chromaThreshold {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX > minX, maxY > minY else { fatalError("no colored region found") }

// Square up the box on its center so the squircle stays symmetric.
let cx = CGFloat(minX + maxX) / 2
let cy = CGFloat(minY + maxY) / 2
let side = CGFloat(max(maxX - minX, maxY - minY))
let inset: CGFloat = 1
let rect = CGRect(x: cx - side / 2 + inset, y: cy - side / 2 + inset,
                  width: side - 2 * inset, height: side - 2 * inset)
let radius = rect.width * 0.2237  // iOS/macOS squircle ratio

print("detected squircle: origin=(\(Int(rect.minX)),\(Int(rect.minY))) side=\(Int(rect.width))")

// Composite: clip to rounded rect, draw original — transparent everywhere else.
let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
)!
do {
    let ctx = NSGraphicsContext(bitmapImageRep: out)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
}

guard let png = out.representation(using: .png, properties: [:]) else {
    fatalError("png encode failed")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
