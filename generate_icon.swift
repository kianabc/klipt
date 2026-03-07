#!/usr/bin/swift
import AppKit

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: rounded rect with gradient
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: deep indigo to vibrant purple
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),
        CGColor(red: 0.35, green: 0.15, blue: 0.55, alpha: 1.0),
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Clipboard shape
    let clipW = s * 0.52
    let clipH = s * 0.58
    let clipX = (s - clipW) / 2
    let clipY = s * 0.15

    // Clipboard body
    let bodyRect = CGRect(x: clipX, y: clipY, width: clipW, height: clipH)
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Clipboard clip (top notch)
    let notchW = s * 0.22
    let notchH = s * 0.08
    let notchX = (s - notchW) / 2
    let notchY = clipY + clipH - notchH / 2
    let notchRect = CGRect(x: notchX, y: notchY, width: notchW, height: notchH)
    let notchPath = CGPath(roundedRect: notchRect, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil)
    ctx.setFillColor(CGColor(red: 0.25, green: 0.15, blue: 0.50, alpha: 1.0))
    ctx.addPath(notchPath)
    ctx.fillPath()

    // Three colored lines representing different clip types
    let lineX = clipX + s * 0.08
    let lineW = clipW - s * 0.16
    let lineH = s * 0.04

    // Blue line (text)
    let line1Y = clipY + clipH * 0.55
    ctx.setFillColor(CGColor(red: 0.25, green: 0.47, blue: 0.95, alpha: 1.0))
    ctx.addPath(CGPath(roundedRect: CGRect(x: lineX, y: line1Y, width: lineW, height: lineH),
                       cornerWidth: lineH/2, cornerHeight: lineH/2, transform: nil))
    ctx.fillPath()

    // Purple line (image)
    let line2Y = clipY + clipH * 0.38
    ctx.setFillColor(CGColor(red: 0.60, green: 0.30, blue: 0.85, alpha: 1.0))
    ctx.addPath(CGPath(roundedRect: CGRect(x: lineX, y: line2Y, width: lineW * 0.7, height: lineH),
                       cornerWidth: lineH/2, cornerHeight: lineH/2, transform: nil))
    ctx.fillPath()

    // Orange line (file)
    let line3Y = clipY + clipH * 0.21
    ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1.0))
    ctx.addPath(CGPath(roundedRect: CGRect(x: lineX, y: line3Y, width: lineW * 0.85, height: lineH),
                       cornerWidth: lineH/2, cornerHeight: lineH/2, transform: nil))
    ctx.fillPath()

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, size: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Saved \(size)x\(size) → \(path)")
}

let basePath = "Klipt/Resources/Assets.xcassets/AppIcon.appiconset"

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let icon = generateIcon(size: size)
    savePNG(icon, size: size, to: "\(basePath)/icon_\(size)x\(size).png")
}
print("Done!")
