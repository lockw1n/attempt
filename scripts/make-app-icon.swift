#!/usr/bin/env swift
//
// make-app-icon.swift — renders Attempt's app icon into Assets.xcassets.
//
// The mark is a loaded barbell on the square's own diagonal: a shaft, two plates a side,
// rotated -45° so the bar's axis matches the canvas diagonal and the ends sit equidistant
// from opposite corners. Colours come from ColorToken.brandAccent (G-7.2).
//
// Geometry is written in a 100x100 space and scaled to the output size, so the same source
// renders any resolution. Emits the three appearance variants AppIcon.appiconset declares.
//
// Usage:  swift scripts/make-app-icon.swift [output-dir] [--size 1024] [--transparent]
//
// --transparent omits the background from the dark and tinted variants, letting the system
// composite its own. Opaque is the default because it always renders; if Xcode's preview of
// the dark or tinted slot looks wrong, re-run with the flag.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry, in a 100x100 canvas

let angleDegrees = -45.0

struct Bar {
    static let shaft = CGRect(x: 8, y: 45.5, width: 84, height: 9)
    static let innerPlates = [CGRect(x: 23, y: 33, width: 10, height: 34),
                              CGRect(x: 67, y: 33, width: 10, height: 34)]
    static let outerPlates = [CGRect(x: 13, y: 39, width: 7.5, height: 22),
                              CGRect(x: 79.5, y: 39, width: 7.5, height: 22)]
}

// MARK: - Appearance variants

struct Variant {
    let filename: String
    let background: (r: Double, g: Double, b: Double)?
    let plate: (r: Double, g: Double, b: Double)
    let shaft: (r: Double, g: Double, b: Double)
    let outerPlateAlpha: Double
}

func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
    (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
}

let transparentVariants = CommandLine.arguments.contains("--transparent")

let variants = [
    Variant(filename: "AppIcon-1024.png",
            background: rgb(0x0B0B0C), plate: rgb(0xFF7A1A), shaft: rgb(0x6A6A72),
            outerPlateAlpha: 1.0),
    Variant(filename: "AppIcon-Dark-1024.png",
            background: transparentVariants ? nil : rgb(0x000000),
            plate: rgb(0xFF7A1A), shaft: rgb(0x5A5A62), outerPlateAlpha: 1.0),
    Variant(filename: "AppIcon-Tinted-1024.png",
            background: transparentVariants ? nil : rgb(0x000000),
            plate: rgb(0xFFFFFF), shaft: rgb(0x8A8A90), outerPlateAlpha: 1.0),
]

// MARK: - Rendering

func parsedSize() -> Int {
    guard let i = CommandLine.arguments.firstIndex(of: "--size"),
          i + 1 < CommandLine.arguments.count,
          let value = Int(CommandLine.arguments[i + 1]) else { return 1024 }
    return value
}

func render(_ variant: Variant, size: Int) -> CGImage? {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    if let background = variant.background {
        context.setFillColor(red: background.r, green: background.g, blue: background.b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Flip to a y-down space so the geometry above reads the way it was drawn, then scale
    // the 100-unit canvas onto the output and rotate about its centre.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    context.scaleBy(x: CGFloat(size) / 100, y: CGFloat(size) / 100)
    context.translateBy(x: 50, y: 50)
    context.rotate(by: CGFloat(angleDegrees) * .pi / 180)
    context.translateBy(x: -50, y: -50)

    func fill(_ rect: CGRect, _ colour: (r: Double, g: Double, b: Double), alpha: Double = 1) {
        let radius = min(rect.width, rect.height) / 2
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                               transform: nil))
        context.setFillColor(red: colour.r, green: colour.g, blue: colour.b, alpha: alpha)
        context.fillPath()
    }

    fill(Bar.shaft, variant.shaft)
    for plate in Bar.outerPlates { fill(plate, variant.plate, alpha: variant.outerPlateAlpha) }
    for plate in Bar.innerPlates { fill(plate, variant.plate) }

    return context.makeImage()
}

// MARK: - Output

let positional = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let outputDirectory = positional.first(where: { Int($0) == nil })
    ?? "Attempt/Assets.xcassets/AppIcon.appiconset"
let size = parsedSize()

for variant in variants {
    guard let image = render(variant, size: size) else {
        FileHandle.standardError.write(Data("could not render \(variant.filename)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(variant.filename)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("could not open \(url.path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("could not write \(url.path)\n".utf8))
        exit(1)
    }
    print("wrote \(url.path) (\(size)x\(size))")
}
