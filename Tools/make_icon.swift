#!/usr/bin/env swift
// 生成 App 图标（1024×1024 PNG）
// 用法：swift Tools/make_icon.swift
import AppKit
import Foundation

let size = 1024.0
let outputPath = "HanziKid/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

// 用显式 1024×1024 的位图上下文，避免 Retina 放大成 2048
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: 1024, pixelsHigh: 1024,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0),
      let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("无法创建位图上下文\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high

// 背景：暖橙渐变（和 App 主色一致）
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.976, green: 0.549, blue: 0.345, alpha: 1),
    NSColor(srgbRed: 0.902, green: 0.384, blue: 0.239, alpha: 1),
])!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// 米字格（淡）
let gridColor = NSColor(srgbRed: 1, green: 0.96, blue: 0.92, alpha: 0.28)
gridColor.setStroke()
let inset = 140.0
let box = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let border = NSBezierPath(rect: box)
border.lineWidth = 6
border.stroke()

let dashes: [(CGPoint, CGPoint)] = [
    (CGPoint(x: size / 2, y: box.minY), CGPoint(x: size / 2, y: box.maxY)),
    (CGPoint(x: box.minX, y: size / 2), CGPoint(x: box.maxX, y: size / 2)),
    (CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY)),
    (CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY)),
]
for (start, end) in dashes {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = 3
    path.setLineDash([12, 14], count: 2, phase: 0)
    path.stroke()
}

// 大字「认」
let character = "认"
var fontSize = 620.0
var font = NSFont(name: "PingFangSC-Semibold", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)

func attributed(_ text: String, _ font: NSFont) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.992, green: 0.973, blue: 0.941, alpha: 1),
    ])
}

// 缩到刚好放进米字格
var textSize = attributed(character, font).size()
while textSize.width > size * 0.76 || textSize.height > size * 0.76 {
    fontSize -= 12
    font = NSFont(name: "PingFangSC-Semibold", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    textSize = attributed(character, font).size()
}

let text = attributed(character, font)
let origin = NSPoint(x: (size - text.size().width) / 2, y: (size - text.size().height) / 2)
text.draw(at: origin)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG 编码失败\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try png.write(to: url)
print("✅ \(outputPath) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
