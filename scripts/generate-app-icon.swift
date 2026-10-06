#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Sources/OATSchedule/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255
    let g = CGFloat((hex >> 8) & 0xff) / 255
    let b = CGFloat(hex & 0xff) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ context: CGContext, path: CGPath, color: CGColor) {
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

func stroke(_ context: CGContext, path: CGPath, color: CGColor, width: CGFloat) {
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func linearGradient(
    _ context: CGContext,
    rect: CGRect,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint
) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: nil
    ) else { return }

    context.saveGState()
    context.addRect(rect)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: Int(canvas) * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("Unable to create bitmap context\n", stderr)
    exit(1)
}

// Work in UIKit-like top-left coordinates.
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)

// MARK: Background
linearGradient(
    context,
    rect: CGRect(x: 0, y: 0, width: canvas, height: canvas),
    colors: [rgb(0xF9FCFF), rgb(0xE8F3FF), rgb(0xF6FAFF)],
    start: CGPoint(x: 90, y: 60),
    end: CGPoint(x: 930, y: 980)
)

// Subtle blue atmospheric glow.
if let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0x4FA8FF, 0.32), rgb(0x4FA8FF, 0.0)] as CFArray,
    locations: [0, 1]
) {
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 760, y: 250),
        startRadius: 10,
        endCenter: CGPoint(x: 760, y: 250),
        endRadius: 460,
        options: []
    )
}

// Inner glass edge, intentionally inset from the system app-icon mask.
let glassFrame = CGRect(x: 42, y: 42, width: 940, height: 940)
fill(context, path: rounded(glassFrame, 205), color: rgb(0xFFFFFF, 0.24))
stroke(context, path: rounded(glassFrame, 205), color: rgb(0xFFFFFF, 0.78), width: 5)

// MARK: Calendar
let calendar = CGRect(x: 272, y: 176, width: 610, height: 635)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 24), blur: 38, color: rgb(0x1B4D8D, 0.18))
fill(context, path: rounded(calendar, 122), color: rgb(0xFFFFFF, 0.97))
context.restoreGState()

// Blue calendar header clipped to the main rounded shape.
context.saveGState()
context.addPath(rounded(calendar, 122))
context.clip()
linearGradient(
    context,
    rect: CGRect(x: calendar.minX, y: calendar.minY, width: calendar.width, height: 190),
    colors: [rgb(0x0868F4), rgb(0x0D8BFA)],
    start: CGPoint(x: calendar.minX, y: calendar.minY),
    end: CGPoint(x: calendar.maxX, y: calendar.minY + 190)
)
context.restoreGState()

// A soft divider between header and body.
let divider = CGMutablePath()
divider.move(to: CGPoint(x: calendar.minX + 24, y: calendar.minY + 184))
divider.addLine(to: CGPoint(x: calendar.maxX - 24, y: calendar.minY + 184))
stroke(context, path: divider, color: rgb(0xD7E8FB, 0.78), width: 3)

// Calendar binding rings.
for x in [400.0, 724.0] {
    let shadowRect = CGRect(x: x - 38, y: 136, width: 76, height: 150)
    fill(context, path: rounded(shadowRect.offsetBy(dx: 0, dy: 14), 38), color: rgb(0x064DBA, 0.55))
    let ring = CGRect(x: x - 31, y: 128, width: 62, height: 142)
    linearGradient(
        context,
        rect: ring,
        colors: [rgb(0xFFFFFF), rgb(0xE8F2FF)],
        start: CGPoint(x: ring.midX, y: ring.minY),
        end: CGPoint(x: ring.midX, y: ring.maxY)
    )
    stroke(context, path: rounded(ring, 31), color: rgb(0xFFFFFF, 0.82), width: 4)
}

// Calendar day cells: deliberately sparse so the mark stays legible at 29 pt.
let cellSize = CGSize(width: 92, height: 92)
let startX: CGFloat = 537
let startY: CGFloat = 352
let gapX: CGFloat = 27
let gapY: CGFloat = 28
for row in 0..<3 {
    for col in 0..<3 {
        let rect = CGRect(
            x: startX + CGFloat(col) * (cellSize.width + gapX),
            y: startY + CGFloat(row) * (cellSize.height + gapY),
            width: cellSize.width,
            height: cellSize.height
        )
        let isAccent = row == 1 && col == 2
        fill(
            context,
            path: rounded(rect, 20),
            color: isAccent ? rgb(0xED2A20) : rgb(0xCFE4FB, 0.88)
        )
    }
}

// MARK: OAT emblem globe
let globeRect = CGRect(x: 106, y: 332, width: 575, height: 575)
let globe = CGPath(ellipseIn: globeRect, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 22), blur: 32, color: rgb(0x0A55A6, 0.19))
linearGradient(
    context,
    rect: globeRect,
    colors: [rgb(0x168CFF), rgb(0x0460E8)],
    start: CGPoint(x: globeRect.minX, y: globeRect.minY),
    end: CGPoint(x: globeRect.maxX, y: globeRect.maxY)
)
context.restoreGState()

// Repaint inside exact circle so the gradient doesn't remain in square corners.
context.saveGState()
context.addPath(globe)
context.clip()
linearGradient(
    context,
    rect: globeRect,
    colors: [rgb(0x158BFF), rgb(0x075EE2)],
    start: CGPoint(x: globeRect.minX, y: globeRect.minY),
    end: CGPoint(x: globeRect.maxX, y: globeRect.maxY)
)
context.restoreGState()

// Globe meridians / parallels.
let white = rgb(0xFFFFFF, 0.96)
let globeLineWidth: CGFloat = 9

let meridian1 = CGMutablePath()
meridian1.move(to: CGPoint(x: 395, y: 339))
meridian1.addCurve(
    to: CGPoint(x: 395, y: 899),
    control1: CGPoint(x: 270, y: 470),
    control2: CGPoint(x: 270, y: 770)
)
stroke(context, path: meridian1, color: white, width: globeLineWidth)

let meridian2 = CGMutablePath()
meridian2.move(to: CGPoint(x: 395, y: 339))
meridian2.addCurve(
    to: CGPoint(x: 395, y: 899),
    control1: CGPoint(x: 520, y: 470),
    control2: CGPoint(x: 520, y: 770)
)
stroke(context, path: meridian2, color: white, width: globeLineWidth)

let upperLatitude = CGMutablePath()
upperLatitude.move(to: CGPoint(x: 164, y: 466))
upperLatitude.addCurve(
    to: CGPoint(x: 626, y: 466),
    control1: CGPoint(x: 270, y: 540),
    control2: CGPoint(x: 520, y: 540)
)
stroke(context, path: upperLatitude, color: white, width: globeLineWidth)

let lowerLatitude = CGMutablePath()
lowerLatitude.move(to: CGPoint(x: 155, y: 744))
lowerLatitude.addCurve(
    to: CGPoint(x: 635, y: 744),
    control1: CGPoint(x: 270, y: 665),
    control2: CGPoint(x: 520, y: 665)
)
stroke(context, path: lowerLatitude, color: white, width: globeLineWidth)

// Red lower swoosh beneath the globe.
let swoosh = CGMutablePath()
swoosh.move(to: CGPoint(x: 126, y: 733))
swoosh.addCurve(
    to: CGPoint(x: 477, y: 911),
    control1: CGPoint(x: 205, y: 878),
    control2: CGPoint(x: 350, y: 936)
)
swoosh.addCurve(
    to: CGPoint(x: 133, y: 772),
    control1: CGPoint(x: 354, y: 902),
    control2: CGPoint(x: 222, y: 844)
)
swoosh.closeSubpath()
fill(context, path: swoosh, color: rgb(0xD9251C))

// MARK: White airplane silhouette crossing the globe.
let plane = CGMutablePath()
plane.move(to: CGPoint(x: 67, y: 505))
plane.addLine(to: CGPoint(x: 280, y: 538))
plane.addLine(to: CGPoint(x: 372, y: 493))
plane.addLine(to: CGPoint(x: 337, y: 551))
plane.addLine(to: CGPoint(x: 616, y: 585))
plane.addLine(to: CGPoint(x: 702, y: 513))
plane.addLine(to: CGPoint(x: 758, y: 521))
plane.addLine(to: CGPoint(x: 708, y: 603))
plane.addLine(to: CGPoint(x: 669, y: 633))
plane.addLine(to: CGPoint(x: 445, y: 616))
plane.addLine(to: CGPoint(x: 350, y: 756))
plane.addLine(to: CGPoint(x: 287, y: 742))
plane.addLine(to: CGPoint(x: 332, y: 603))
plane.addLine(to: CGPoint(x: 266, y: 592))
plane.addLine(to: CGPoint(x: 187, y: 639))
plane.addLine(to: CGPoint(x: 145, y: 628))
plane.addLine(to: CGPoint(x: 169, y: 573))
plane.closeSubpath()
fill(context, path: plane, color: rgb(0xFFFFFF))

// Tiny fuselage detail.
fill(
    context,
    path: rounded(CGRect(x: 374, y: 542, width: 108, height: 24), 12),
    color: rgb(0x0B6FEB)
)

// Tail color block inspired by the supplied ОмАВИАТ mark.
let tailBlue = CGMutablePath()
tailBlue.move(to: CGPoint(x: 643, y: 560))
tailBlue.addLine(to: CGPoint(x: 704, y: 517))
tailBlue.addLine(to: CGPoint(x: 756, y: 525))
tailBlue.addLine(to: CGPoint(x: 719, y: 581))
tailBlue.closeSubpath()
fill(context, path: tailBlue, color: rgb(0x0B70EF))

let tailRed = CGMutablePath()
tailRed.move(to: CGPoint(x: 651, y: 586))
tailRed.addLine(to: CGPoint(x: 719, y: 592))
tailRed.addLine(to: CGPoint(x: 691, y: 644))
tailRed.addLine(to: CGPoint(x: 646, y: 635))
tailRed.closeSubpath()
fill(context, path: tailRed, color: rgb(0xD9251C))

// White/blue tail cap.
let tailCap = CGMutablePath()
tailCap.move(to: CGPoint(x: 704, y: 517))
tailCap.addLine(to: CGPoint(x: 772, y: 519))
tailCap.addLine(to: CGPoint(x: 758, y: 566))
tailCap.addLine(to: CGPoint(x: 719, y: 557))
tailCap.closeSubpath()
fill(context, path: tailCap, color: rgb(0xFFFFFF))
stroke(context, path: tailCap, color: rgb(0x0B70EF), width: 4)

// Soft specular sweep over the upper-right of the icon. The system will add
// its own Liquid Glass treatment too, but this keeps the fallback icon airy.
let highlight = CGMutablePath()
highlight.move(to: CGPoint(x: 580, y: 92))
highlight.addCurve(
    to: CGPoint(x: 930, y: 340),
    control1: CGPoint(x: 760, y: 62),
    control2: CGPoint(x: 902, y: 170)
)
highlight.addCurve(
    to: CGPoint(x: 614, y: 202),
    control1: CGPoint(x: 842, y: 268),
    control2: CGPoint(x: 720, y: 219)
)
highlight.closeSubpath()
fill(context, path: highlight, color: rgb(0xFFFFFF, 0.20))

// Undo the top-left transform before exporting.
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 0, y: -canvas)

guard let image = context.makeImage() else {
    fputs("Unable to create CGImage\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create PNG destination\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, image, nil)
if !CGImageDestinationFinalize(destination) {
    fputs("Unable to write PNG\n", stderr)
    exit(1)
}

print("Generated app icon: \(outputURL.path)")
